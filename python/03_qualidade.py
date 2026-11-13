"""Etapa 2 - Qualidade de dados.

  1. Profiling de todas as tabelas de origem e das fontes externas
     -> tabela dw_campo_real.dq_profiling
  2. Regras de validação (pelo menos uma por dimensão de qualidade)
     -> tabela dw_campo_real.dq_metricas

As regras são funções pequenas e reutilizáveis: recebem um DataFrame e
devolvem só as linhas que falharam. Este script NÃO altera nenhum dado,
ele só mede. A limpeza é feita na carga do DW (sql/05_dw_carga.sql).
"""

from datetime import datetime

import pandas as pd
from sqlalchemy import text

from banco import conectar, ler_config

AGORA = datetime.now()

# estados de cada submercado (para conferir UF x submercado no cadastro)
UFS_DO_SUBMERCADO = {
    "SE": ["SP", "RJ", "MG", "ES", "GO", "MT", "MS", "DF", "AC", "RO"],
    "S":  ["PR", "SC", "RS"],
    "NE": ["BA", "SE", "AL", "PE", "PB", "RN", "CE", "PI"],
    "N":  ["PA", "TO", "MA", "AM", "AP"],
}


# =====================================================================
# REGRAS REUTILIZÁVEIS (devolvem as linhas com falha)
# =====================================================================

def nulos(df, coluna):
    """Completude: linhas em que a coluna está vazia (NULL)."""
    return df[df[coluna].isna()]


def texto_vazio(df, coluna):
    """Completude: linhas em que o texto está nulo ou em branco."""
    return df[df[coluna].isna() | (df[coluna].astype(str).str.strip() == "")]


def horas_faltando(df, coluna_grupo, inicio, fim):
    """Completude: horas que deveriam existir para cada grupo e não existem.
    Devolve (horas que faltam, total de horas esperadas)."""
    todas = pd.date_range(inicio, fim, freq="h")
    faltas = []
    for grupo, parte in df.groupby(coluna_grupo):
        for hora in todas.difference(parte["data_hora"]):
            faltas.append({coluna_grupo: grupo, "data_hora": hora})
    esperadas = len(todas) * df[coluna_grupo].nunique()
    return pd.DataFrame(faltas, columns=[coluna_grupo, "data_hora"]), esperadas


def duplicados(df, colunas):
    """Unicidade: linhas repetidas na chave (a primeira não conta como falha)."""
    return df[df.duplicated(subset=colunas, keep="first")]


def fora_da_faixa(df, coluna, minimo=None, maximo=None):
    """Validade: valores abaixo do mínimo ou acima do máximo."""
    falha = pd.Series(False, index=df.index)
    if minimo is not None:
        falha = falha | (df[coluna] < minimo)
    if maximo is not None:
        falha = falha | (df[coluna] > maximo)
    return df[falha]


def fora_do_padrao(df, coluna, padrao):
    """Validade: texto que não segue o formato esperado (expressão regular)."""
    return df[~df[coluna].astype(str).str.match(padrao)]


def sem_cadastro(df, coluna, df_cadastro, coluna_cadastro):
    """Integridade referencial: valor preenchido que não existe no cadastro."""
    preenchidos = df[df[coluna].notna()]
    return preenchidos[~preenchidos[coluna].isin(df_cadastro[coluna_cadastro])]


def valor_travado(df, coluna_grupo, coluna_valor, minimo_horas):
    """Acurácia: o mesmo valor (diferente de zero) repetido por várias
    horas seguidas, sinal de medidor travado."""
    d = df.sort_values([coluna_grupo, "data_hora"]).copy()
    mudou = (d[coluna_valor] != d[coluna_valor].shift()) | (d[coluna_grupo] != d[coluna_grupo].shift())
    d["bloco"] = mudou.cumsum()
    d["tamanho"] = d.groupby("bloco")[coluna_valor].transform("size")
    return d[(d["tamanho"] >= minimo_horas) & (d[coluna_valor] > 0)]


def chegou_atrasado(df, limite_horas):
    """Atualidade: dado que chegou mais de X horas depois da hora medida."""
    atraso = df["recebido_em"] - df["data_hora"]
    return df[atraso > pd.Timedelta(hours=limite_horas)]


# =====================================================================
# PROFILING
# =====================================================================

def perfil_da_tabela(nome, df):
    """Uma linha por coluna: tipo, nulos, distintos, mínimo, máximo, média e mediana."""
    linhas = []
    for coluna in df.columns:
        serie = df[coluna]
        preenchidos = serie.dropna()
        numerica = pd.api.types.is_numeric_dtype(serie) and not pd.api.types.is_bool_dtype(serie)
        linhas.append({
            "tabela": nome,
            "coluna": coluna,
            "tipo": str(serie.dtype),
            "total_linhas": len(serie),
            "nulos": int(serie.isna().sum()),
            "distintos": int(serie.nunique()),
            "minimo": str(preenchidos.min())[:60] if len(preenchidos) else None,
            "maximo": str(preenchidos.max())[:60] if len(preenchidos) else None,
            "media": float(preenchidos.mean()) if numerica and len(preenchidos) else None,
            "mediana": float(preenchidos.median()) if numerica and len(preenchidos) else None,
            "data_execucao": AGORA,
        })
    return linhas


# =====================================================================
# EXECUÇÃO
# =====================================================================

def main():
    config = ler_config()
    origem = conectar(config, "banco_origem")
    dw = conectar(config, "banco_dw")
    q = config["qualidade"]

    # ---------- leitura das tabelas ----------
    tabelas = {}
    for nome in ["submercado", "fonte_energia", "usina", "feriado_nacional", "parada_usina",
                 "medicao_geracao", "stg_pld_horario", "pld_horario", "clima_horario"]:
        tabelas[nome] = pd.read_sql(f"SELECT * FROM {nome}", origem)
    pld_raw = pd.read_sql("SELECT * FROM vw_pld_raw", origem)

    usina = tabelas["usina"]
    fonte = tabelas["fonte_energia"]
    parada = tabelas["parada_usina"]
    med = tabelas["medicao_geracao"]
    pld = tabelas["pld_horario"]
    clima = tabelas["clima_horario"]

    # ---------- 1. profiling ----------
    perfil = []
    for nome, df in tabelas.items():
        perfil.extend(perfil_da_tabela(nome, df))
    perfil = pd.DataFrame(perfil)

    # ---------- 2. regras ----------
    resultados = []

    def registrar(regra, dimensao, tabela, avaliados, falhas, decisao):
        """Guarda o resultado de uma regra (falhas pode ser DataFrame ou número)."""
        quantidade = falhas if isinstance(falhas, int) else len(falhas)
        resultados.append({
            "regra": regra, "dimensao": dimensao, "tabela": tabela,
            "registros_avaliados": avaliados, "registros_falha": quantidade,
            "percentual_falha": round(100 * quantidade / avaliados, 4) if avaliados else 0,
            "decisao": decisao, "data_execucao": AGORA,
        })

    # medição junto com o cadastro da usina (para as regras que cruzam tabelas)
    cadastro = usina.merge(fonte, on="id_fonte")[["id_usina", "cod_usina", "cod_fonte", "potencia_mw"]]
    med_usina = med.merge(cadastro, on="id_usina", how="left")
    med_2025 = med[med["data_hora"].dt.year == 2025]          # só o período válido
    med_cadastrada = med_2025[med_2025["id_usina"].isin(usina["id_usina"])]

    # ===== COMPLETUDE =====
    registrar("Energia gerada sem valor (NULL)", "Completude", "medicao_geracao",
              len(med), nulos(med, "energia_mwh"),
              "Sinalizar: fica NULL no DW (não inventamos leitura)")
    registrar("Medição sem usina informada", "Completude", "medicao_geracao",
              len(med), nulos(med, "id_usina"),
              "Sinalizar: vai para o membro 'Usina desconhecida' do DW")
    faltas, esperadas = horas_faltando(med_cadastrada, "id_usina", "2025-01-01 00:00", "2025-12-31 23:00")
    registrar("Horas de 2025 sem medição (por usina)", "Completude", "medicao_geracao",
              esperadas, faltas,
              "Sinalizar: as horas ficam sem linha no fato (não inventamos)")
    registrar("Município da usina em branco", "Completude", "usina",
              len(usina), texto_vazio(usina, "municipio"),
              "Descartar: é o cadastro duplicado da EOL Ventos do Potiguar")
    faltas, esperadas = horas_faltando(pld, "cod_submercado", "2025-01-01 00:00", pld["data_hora"].max())
    registrar("Horas sem PLD (por submercado)", "Completude", "pld_horario",
              esperadas, faltas,
              "Corrigir: recuperar as horas da camada raw (stg_pld_horario)")
    registrar("Clima com algum valor nulo", "Completude", "clima_horario",
              len(clima), clima[clima[["temperatura_c", "radiacao_wm2", "vento_kmh", "chuva_mm"]].isna().any(axis=1)],
              "Nenhuma ação necessária")
    faltas, esperadas = horas_faltando(clima, "cod_usina", "2025-01-01 00:00", "2025-12-31 23:00")
    registrar("Horas de 2025 sem clima (por usina)", "Completude", "clima_horario",
              esperadas, faltas, "Nenhuma ação necessária")

    # ===== UNICIDADE =====
    registrar("Mesma usina e mesma hora mais de uma vez", "Unicidade", "medicao_geracao",
              len(med), duplicados(med, ["id_usina", "data_hora"]),
              "Quarentena: fica a leitura SCADA; se as duas são SCADA, a que chegou primeiro")
    nomes = usina.assign(nome_limpo=usina["nome"].str.strip().str.lower())
    registrar("Usina cadastrada duas vezes (mesmo nome)", "Unicidade", "usina",
              len(usina), duplicados(nomes, ["nome_limpo"]),
              "Descartar o cadastro com código fora do padrão (CRE-EOL-07)")
    registrar("PLD raw repetido (submercado e hora)", "Unicidade", "stg_pld_horario",
              len(pld_raw), duplicados(pld_raw, ["cod_submercado", "data_hora"]),
              "Nenhuma ação necessária")

    # ===== VALIDADE =====
    registrar("Energia gerada negativa", "Validade", "medicao_geracao",
              len(med), fora_da_faixa(med, "energia_mwh", minimo=0),
              "Corrigir para 0: valor negativo é consumo próprio, geração foi zero")
    registrar("Data da medição fora de 2025", "Validade", "medicao_geracao",
              len(med), med[med["data_hora"].dt.year != 2025],
              "Quarentena: ano digitado errado (2052) e já existe leitura dessa hora")
    registrar("Código da usina fora do padrão CRE-XXX-999", "Validade", "usina",
              len(usina), fora_do_padrao(usina, "cod_usina", r"^CRE-[A-Z]{3}-\d{3}$"),
              "Descartar: é o cadastro duplicado")
    fora_lat = fora_da_faixa(usina, "latitude", minimo=-34, maximo=6)
    fora_lon = fora_da_faixa(usina, "longitude", minimo=-74, maximo=-34)
    registrar("Coordenadas fora do Brasil", "Validade", "usina",
              len(usina), pd.concat([fora_lat, fora_lon]).drop_duplicates(),
              "Corrigir o sinal da latitude (Janaúba/MG fica em -15,80)")
    registrar("Início de operação no futuro", "Validade", "usina",
              len(usina), usina[pd.to_datetime(usina["data_inicio_operacao"]) > AGORA],
              "Sinalizar: data vira NULL no DW (não sabemos a data certa)")
    registrar("Parada com fim antes do início", "Validade", "parada_usina",
              len(parada), parada[parada["fim"] < parada["inicio"]],
              "Descartar a parada: não dá para saber o horário certo")
    fora_limite = []
    for ano in sorted(pld["data_hora"].dt.year.unique()):
        do_ano = pld[pld["data_hora"].dt.year == ano]
        fora_limite.append(fora_da_faixa(do_ano, "pld_rs_mwh",
                                         minimo=float(q[f"pld_min_{ano}"]),
                                         maximo=float(q[f"pld_max_{ano}"])))
    registrar("PLD fora dos limites regulatórios da ANEEL", "Validade", "pld_horario",
              len(pld), pd.concat(fora_limite),
              "Corrigir: usar o valor original guardado na camada raw")

    # ===== CONSISTÊNCIA =====
    solar = med_usina[med_usina["cod_fonte"] == "UFV"]
    de_noite = (solar["data_hora"].dt.hour < 6) | (solar["data_hora"].dt.hour > 18)
    registrar("Usina solar gerando de noite", "Consistência", "medicao_geracao",
              len(solar), solar[de_noite & (solar["energia_mwh"] > 0)],
              "Corrigir para 0: sem sol não há geração (relógio do medidor errado)")
    registrar("Geração com disponibilidade zero (usina parada)", "Consistência", "medicao_geracao",
              len(med), med[(med["disponibilidade_mw"] == 0) & (med["energia_mwh"] > 0)],
              "Corrigir para 0: a parada programada e a disponibilidade confirmam")
    registrar("Dado recebido antes da hora medida", "Consistência", "medicao_geracao",
              len(med_2025), med_2025[med_2025["recebido_em"] < med_2025["data_hora"]],
              "Sinalizar: energia é mantida, só o relógio do servidor estava errado")
    uf_errada = usina[usina.apply(
        lambda u: u["uf"] not in UFS_DO_SUBMERCADO.get(u["cod_submercado"], []), axis=1)]
    registrar("UF não pertence ao submercado da usina", "Consistência", "usina",
              len(usina), uf_errada,
              "Corrigir para SP: Sertãozinho e as coordenadas ficam em São Paulo")
    comparacao = pld.merge(pld_raw, on=["cod_submercado", "data_hora"], suffixes=("", "_raw"))
    registrar("PLD tratado diferente do raw", "Consistência", "pld_horario",
              len(comparacao), comparacao[comparacao["pld_rs_mwh"] != comparacao["pld_rs_mwh_raw"]],
              "Corrigir: vale o raw, que é o dado como veio da CCEE")

    # ===== ACURÁCIA =====
    com_potencia = med_usina[med_usina["potencia_mw"].notna()]
    registrar("Energia da hora maior que a potência instalada", "Acurácia", "medicao_geracao",
              len(com_potencia), com_potencia[com_potencia["energia_mwh"] > com_potencia["potencia_mw"]],
              "Lançamento manual em kWh: dividir por 1000. Outros casos: NULL (leitura impossível)")
    registrar("Mesmo valor repetido por 6 horas ou mais (medidor travado)", "Acurácia", "medicao_geracao",
              len(med_cadastrada), valor_travado(med_cadastrada, "id_usina", "energia_mwh", 6),
              "Sinalizar: valor é plausível, fica no DW com a marca MEDIDOR_TRAVADO")
    registrar("Temperatura ou radiação fora do possível", "Acurácia", "clima_horario",
              len(clima), pd.concat([fora_da_faixa(clima, "temperatura_c", -15, 50),
                                     fora_da_faixa(clima, "radiacao_wm2", 0, 1400)]).drop_duplicates(),
              "Nenhuma ação necessária")

    # ===== INTEGRIDADE REFERENCIAL =====
    registrar("Medição de usina que não existe no cadastro", "Integridade referencial", "medicao_geracao",
              len(med), sem_cadastro(med, "id_usina", usina, "id_usina"),
              "Sinalizar: vai para o membro 'Usina desconhecida' do DW")
    registrar("Parada de usina que não existe no cadastro", "Integridade referencial", "parada_usina",
              len(parada), sem_cadastro(parada, "id_usina", usina, "id_usina"),
              "Nenhuma ação necessária")
    registrar("Clima de usina que não existe no cadastro", "Integridade referencial", "clima_horario",
              len(clima), sem_cadastro(clima, "cod_usina", usina, "cod_usina"),
              "Nenhuma ação necessária")

    # ===== ATUALIDADE =====
    limite = int(q["atraso_maximo_horas"])
    registrar(f"Medição recebida mais de {limite} h depois", "Atualidade", "medicao_geracao",
              len(med_2025), chegou_atrasado(med_2025, limite),
              "Sinalizar: energia é mantida, fica a marca ATRASADO")
    ultima = med_cadastrada.groupby("id_usina")["data_hora"].max()
    registrar("Usina que parou de enviar dados antes do fim do ano", "Atualidade", "medicao_geracao",
              len(ultima), int((ultima < pd.Timestamp("2025-12-31 23:00")).sum()),
              "Sinalizar: UFV Campo Real Minas sem dados desde 29/12")

    metricas = pd.DataFrame(resultados)

    # ---------- 3. grava no banco (substitui a execução anterior) ----------
    with dw.begin() as con:
        con.execute(text("TRUNCATE TABLE dq_profiling"))
        con.execute(text("TRUNCATE TABLE dq_metricas"))
        perfil.to_sql("dq_profiling", con, if_exists="append", index=False)
        metricas.to_sql("dq_metricas", con, if_exists="append", index=False)

    print(f"Profiling: {len(perfil)} colunas de {len(tabelas)} tabelas")
    print(f"Regras: {len(metricas)} ({(metricas['registros_falha'] > 0).sum()} com falha)\n")
    print(metricas[["dimensao", "tabela", "regra", "registros_avaliados",
                    "registros_falha"]].to_string(index=False))


if __name__ == "__main__":
    main()
