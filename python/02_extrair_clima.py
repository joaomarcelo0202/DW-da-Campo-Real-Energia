"""Etapa 1 (obrigatório B) - Clima horário da Open-Meteo.

Para cada usina do cadastro, busca na API de histórico da Open-Meteo o
clima horário de 2025 nas coordenadas da usina (temperatura, radiação
solar, vento e chuva).

  - raw_clima_openmeteo: guarda o JSON inteiro que a API devolveu;
  - clima_horario: tabela tratada, 1 linha por usina e por hora.

O que já foi baixado não é baixado de novo: se a usina já tem o período
no raw, o script reaproveita o JSON guardado.
"""

import json
import time

import pandas as pd
import requests
from sqlalchemy import text

from banco import conectar, finalizar_log, iniciar_log, ler_config

TENTATIVAS = 3


def ler_usinas(engine):
    """Lê as usinas do cadastro de origem.
    Dois cuidados por causa de problemas de qualidade do cadastro:
      - o código tem que estar no padrão CRE-XXX-999 (tira o cadastro duplicado);
      - o Brasil fica quase todo no hemisfério sul: latitude maior que 6 está
        com o sinal errado (caso da UFV Campo Real Minas), então invertemos.
    """
    usinas = pd.read_sql(
        "SELECT cod_usina, latitude, longitude FROM usina "
        "WHERE cod_usina REGEXP '^CRE-[A-Z]{3}-[0-9]{3}$' ORDER BY cod_usina", engine)
    usinas["latitude"] = usinas["latitude"].astype(float)
    usinas["longitude"] = usinas["longitude"].astype(float)
    errada = usinas["latitude"] > 6
    usinas.loc[errada, "latitude"] = -usinas.loc[errada, "latitude"]
    return usinas


def pedir_clima(url, parametros):
    """GET com tempo limite e nova tentativa. Devolve o texto da resposta."""
    for tentativa in range(1, TENTATIVAS + 1):
        try:
            resposta = requests.get(url, params=parametros, timeout=60)
        except requests.exceptions.RequestException as erro:
            if tentativa == TENTATIVAS:
                raise RuntimeError(f"Falha de rede depois de {TENTATIVAS} tentativas: {erro}")
            time.sleep(5 * tentativa)
            continue

        if resposta.status_code == 200:
            return resposta.text
        if resposta.status_code == 429 or resposta.status_code >= 500:
            if tentativa == TENTATIVAS:
                raise RuntimeError(f"API respondeu HTTP {resposta.status_code} depois de {TENTATIVAS} tentativas")
            time.sleep(15 * tentativa)   # limite de requisições: espera e tenta de novo
            continue
        raise RuntimeError(f"API respondeu HTTP {resposta.status_code}: {resposta.text[:200]}")


def buscar_raw_guardado(engine, cod_usina, inicio, fim):
    """Devolve o JSON já baixado dessa usina e período, se existir."""
    with engine.connect() as con:
        return con.execute(
            text("SELECT resposta_json FROM raw_clima_openmeteo "
                 "WHERE cod_usina = :u AND data_inicio = :i AND data_fim = :f "
                 "ORDER BY id_raw DESC LIMIT 1"),
            {"u": cod_usina, "i": inicio, "f": fim}).scalar()


def tratar(cod_usina, texto_json, variaveis):
    """JSON da API -> DataFrame no formato da tabela clima_horario."""
    dados = json.loads(texto_json)
    horario = dados.get("hourly")
    if not horario or not horario.get("time"):
        raise RuntimeError("A API devolveu resposta vazia")
    faltando = [v for v in variaveis if v not in horario]
    if faltando:
        raise RuntimeError(f"A API mudou as colunas. Faltando: {faltando}")

    return pd.DataFrame({
        "cod_usina": cod_usina,
        "data_hora": pd.to_datetime(horario["time"]),
        "temperatura_c": horario["temperature_2m"],
        "radiacao_wm2": horario["shortwave_radiation"],
        "vento_kmh": horario["wind_speed_100m"],
        "chuva_mm": horario["precipitation"],
    })


def extrair_usina(engine, config, usina):
    clima = config["clima"]
    cod = usina["cod_usina"]
    inicio, fim = clima["data_inicio"], clima["data_fim"]
    variaveis = clima["variaveis"].split(",")

    id_log = iniciar_log(engine, f"CLIMA {cod}", clima["url_api"])
    try:
        texto_json = buscar_raw_guardado(engine, cod, inicio, fim)
        status = "JA_BAIXADO"
        if texto_json is None:
            texto_json = pedir_clima(clima["url_api"], {
                "latitude": usina["latitude"], "longitude": usina["longitude"],
                "start_date": inicio, "end_date": fim,
                "hourly": clima["variaveis"], "timezone": clima["fuso"],
            })
            status = "OK"
            with engine.begin() as con:      # grava o raw como chegou
                con.execute(
                    text("INSERT INTO raw_clima_openmeteo (cod_usina, latitude, longitude, "
                         "data_inicio, data_fim, resposta_json, origem) "
                         "VALUES (:u, :lat, :lon, :i, :f, :j, :o)"),
                    {"u": cod, "lat": usina["latitude"], "lon": usina["longitude"],
                     "i": inicio, "f": fim, "j": texto_json, "o": clima["url_api"]})
            time.sleep(2)                    # pausa entre uma usina e outra

        df = tratar(cod, texto_json, variaveis)
        with engine.begin() as con:          # regrava a tratada da usina
            con.execute(text("DELETE FROM clima_horario WHERE cod_usina = :u"), {"u": cod})
            df.to_sql("clima_horario", con, if_exists="append", index=False,
                      chunksize=2000, method="multi")
        finalizar_log(engine, id_log, status, len(df), len(df))
        print(f"{cod}: {len(df)} horas ({status})")
    except Exception as erro:
        finalizar_log(engine, id_log, "ERRO", erro=erro)
        print(f"{cod}: ERRO ({erro})")


def main():
    config = ler_config()
    engine = conectar(config, "banco_origem")
    for _, usina in ler_usinas(engine).iterrows():
        extrair_usina(engine, config, usina)


if __name__ == "__main__":
    main()
