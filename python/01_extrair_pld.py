"""Etapa 1 (obrigatório A) - PLD horário da CCEE.

O que o script faz, para cada ano do config.ini:
  1. tenta buscar o PLD pela API do portal de dados abertos (CKAN),
     paginando de 5.000 em 5.000 linhas;
  2. se a API falhar (hoje ela devolve "acesso bloqueado", HTTP 403),
     grava o erro no log e lê o CSV do mesmo recurso, baixado do portal;
  3. grava o dado como chegou na camada raw (stg_pld_horario);
  4. no fim, transforma o raw na tabela tratada (pld_horario).

Rodar de novo não duplica: o raw do arquivo é apagado antes de regravar e
a tabela tratada usa a chave (cod_submercado, data_hora).
"""

import time

import pandas as pd
import requests
from sqlalchemy import text

from banco import PASTA_PROJETO, conectar, finalizar_log, iniciar_log, ler_config

COLUNAS_ESPERADAS = ["MES_REFERENCIA", "SUBMERCADO", "PERIODO_COMERCIALIZACAO",
                     "DIA", "HORA", "PLD_HORA"]
TAMANHO_PAGINA = 5000
TENTATIVAS = 3


def pedir_pagina(url, parametros):
    """Faz um GET com tempo limite e nova tentativa.
    Tenta de novo em erro de rede, tempo limite, erro 5xx e limite de
    requisições (429). Outros erros (como o 403 de bloqueio) param na hora."""
    for tentativa in range(1, TENTATIVAS + 1):
        try:
            resposta = requests.get(url, params=parametros, timeout=60)
        except requests.exceptions.RequestException as erro:
            if tentativa == TENTATIVAS:
                raise RuntimeError(f"Falha de rede depois de {TENTATIVAS} tentativas: {erro}")
            time.sleep(5 * tentativa)
            continue

        if resposta.status_code == 200:
            return resposta.json()
        if resposta.status_code == 429 or resposta.status_code >= 500:
            if tentativa == TENTATIVAS:
                raise RuntimeError(f"API respondeu HTTP {resposta.status_code} depois de {TENTATIVAS} tentativas")
            time.sleep(10 * tentativa)   # espera mais a cada tentativa
            continue
        raise RuntimeError(f"API respondeu HTTP {resposta.status_code} (acesso negado ou recurso não existe)")


def extrair_pela_api(url, id_recurso):
    """Busca todas as linhas de um recurso, aumentando o offset até acabar."""
    linhas = []
    offset = 0
    while True:
        dados = pedir_pagina(url, {"resource_id": id_recurso,
                                   "limit": TAMANHO_PAGINA, "offset": offset})
        registros = dados["result"]["records"]
        if not registros:          # página vazia = acabou
            break
        linhas.extend(registros)
        offset += TAMANHO_PAGINA
        if offset >= dados["result"].get("total", 0):
            break
        time.sleep(1)              # respeita o limite de requisições
    return pd.DataFrame(linhas, dtype=str)


def extrair_do_csv(arquivo):
    """Lê o CSV baixado do portal, tudo como texto (sem mexer em nada)."""
    return pd.read_csv(arquivo, sep=";", dtype=str, keep_default_na=False)


def conferir_colunas(df):
    """Trata resposta vazia e mudança de colunas."""
    if df.empty:
        raise RuntimeError("A fonte devolveu zero linhas")
    df.columns = [c.strip().upper() for c in df.columns]
    faltando = [c for c in COLUNAS_ESPERADAS if c not in df.columns]
    if faltando:
        raise RuntimeError(f"A fonte mudou as colunas. Faltando: {faltando}")
    return df


def gravar_raw(engine, df, nome_origem):
    """Grava na camada raw exatamente como veio (tudo texto)."""
    raw = pd.DataFrame({
        "id_ckan": df["_ID"] if "_ID" in df.columns else None,
        "mes_referencia": df["MES_REFERENCIA"],
        "submercado": df["SUBMERCADO"],
        "periodo_comercializacao": df["PERIODO_COMERCIALIZACAO"],
        "dia": df["DIA"],
        "hora": df["HORA"],
        "pld_hora": df["PLD_HORA"],
        "arquivo_origem": nome_origem,
    })
    with engine.begin() as con:
        # apaga o que já tinha dessa mesma origem para não duplicar
        con.execute(text("DELETE FROM stg_pld_horario WHERE arquivo_origem = :o"),
                    {"o": nome_origem})
        raw.to_sql("stg_pld_horario", con, if_exists="append", index=False,
                   chunksize=5000, method="multi")
    return len(raw)


def extrair_ano(engine, config, ano):
    pld = config["pld"]
    id_recurso = pld[f"recurso_{ano}"]
    nome_origem = f"pld_horario_{ano}"

    # 1) tenta a API
    if pld["tentar_api"].strip().lower() == "sim":
        id_log = iniciar_log(engine, f"PLD {ano}", f"API CCEE recurso {id_recurso}")
        try:
            df = conferir_colunas(extrair_pela_api(pld["url_api"], id_recurso))
            gravadas = gravar_raw(engine, df, nome_origem + " (API)")
            finalizar_log(engine, id_log, "OK", len(df), gravadas)
            print(f"PLD {ano}: {gravadas} linhas pela API")
            return
        except Exception as erro:
            finalizar_log(engine, id_log, "ERRO", erro=erro)
            print(f"PLD {ano}: API falhou ({erro}). Vou usar o CSV.")

    # 2) plano B: CSV do mesmo recurso, baixado do portal
    arquivo = PASTA_PROJETO / pld["pasta_csv"] / f"pld_horario_{ano}.csv"
    id_log = iniciar_log(engine, f"PLD {ano}", f"CSV {arquivo.name}")
    try:
        df = conferir_colunas(extrair_do_csv(arquivo))
        gravadas = gravar_raw(engine, df, arquivo.name)
        finalizar_log(engine, id_log, "OK", len(df), gravadas)
        print(f"PLD {ano}: {gravadas} linhas pelo CSV")
    except Exception as erro:
        finalizar_log(engine, id_log, "ERRO", erro=erro)
        print(f"PLD {ano}: ERRO no CSV ({erro})")


def tratar(engine):
    """Raw -> tabela tratada pld_horario (tipos certos e sem duplicar)."""
    id_log = iniciar_log(engine, "PLD tratado", "stg_pld_horario")
    try:
        with engine.begin() as con:
            lidas = con.execute(text("SELECT COUNT(*) FROM vw_pld_raw")).scalar()
            con.execute(text("""
                INSERT INTO pld_horario (cod_submercado, data_hora, mes_referencia,
                                         periodo_comercializacao, pld_rs_mwh, origem)
                SELECT cod_submercado, data_hora, mes_referencia,
                       periodo_comercializacao, pld_rs_mwh, 'CCEE'
                FROM vw_pld_raw
                WHERE cod_submercado IS NOT NULL AND data_hora IS NOT NULL
                ON DUPLICATE KEY UPDATE pld_rs_mwh = VALUES(pld_rs_mwh),
                                        origem     = VALUES(origem)
            """))
            gravadas = con.execute(text("SELECT COUNT(*) FROM pld_horario")).scalar()
        finalizar_log(engine, id_log, "OK", lidas, gravadas)
        print(f"pld_horario: {gravadas} linhas")
    except Exception as erro:
        finalizar_log(engine, id_log, "ERRO", erro=erro)
        raise


def main():
    config = ler_config()
    engine = conectar(config, "banco_origem")
    for ano in config["pld"]["anos"].split(","):
        extrair_ano(engine, config, ano.strip())
    tratar(engine)


if __name__ == "__main__":
    main()
