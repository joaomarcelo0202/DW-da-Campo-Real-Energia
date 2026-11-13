"""Etapa 2 - Relatório antes x depois da limpeza.

Compara os indicadores de negócio calculados de dois jeitos:
  ANTES : direto nas tabelas de origem, sem nenhum tratamento;
  DEPOIS: no data warehouse, com os dados limpos.

Grava o resultado em dw_campo_real.dq_antes_depois.
Rodar DEPOIS do sql/05_dw_carga.sql.
"""

from datetime import datetime

import pandas as pd
from sqlalchemy import text

from banco import conectar, ler_config

SQL_ANTES = """
    SELECT u.cod_usina AS recorte,
           SUM(m.energia_mwh)                AS geracao_mwh,
           SUM(m.energia_mwh * p.pld_rs_mwh) AS receita_rs,
           MAX(u.potencia_mw) * 8760         AS capacidade_mwh
    FROM medicao_geracao m
    JOIN usina u            ON u.id_usina = m.id_usina
    LEFT JOIN pld_horario p ON p.cod_submercado = u.cod_submercado
                           AND p.data_hora      = m.data_hora
    GROUP BY u.cod_usina
"""

SQL_DEPOIS = """
    SELECT u.cod_usina AS recorte,
           SUM(f.energia_mwh)        AS geracao_mwh,
           SUM(f.receita_rs)         AS receita_rs,
           MAX(u.potencia_mw) * 8760 AS capacidade_mwh
    FROM fato_geracao f
    JOIN dim_usina u ON u.sk_usina = f.sk_usina
    WHERE f.sk_usina <> -1
    GROUP BY u.cod_usina
"""


def com_total_e_indicadores(df):
    """Acrescenta a linha Total e calcula preço capturado e fator de capacidade."""
    total = pd.DataFrame([{
        "recorte": "Total",
        "geracao_mwh": df["geracao_mwh"].sum(),
        "receita_rs": df["receita_rs"].sum(),
        "capacidade_mwh": df["capacidade_mwh"].sum(),
    }])
    df = pd.concat([df, total], ignore_index=True)
    df["preco_capturado_rs_mwh"] = df["receita_rs"] / df["geracao_mwh"]
    df["fator_capacidade_pct"] = 100 * df["geracao_mwh"] / df["capacidade_mwh"]
    return df.drop(columns="capacidade_mwh")


def main():
    config = ler_config()
    antes = com_total_e_indicadores(pd.read_sql(SQL_ANTES, conectar(config, "banco_origem")))
    dw = conectar(config, "banco_dw")
    depois = com_total_e_indicadores(pd.read_sql(SQL_DEPOIS, dw))

    # deixa uma linha por indicador e recorte, com o valor antes e o depois
    antes = antes.melt(id_vars="recorte", var_name="indicador", value_name="valor_antes")
    depois = depois.melt(id_vars="recorte", var_name="indicador", value_name="valor_depois")
    comparacao = antes.merge(depois, on=["recorte", "indicador"], how="outer")
    comparacao["diferenca"] = comparacao["valor_depois"] - comparacao["valor_antes"]
    comparacao["diferenca_pct"] = 100 * comparacao["diferenca"] / comparacao["valor_antes"]
    comparacao = comparacao.round(2)
    comparacao["data_execucao"] = datetime.now()

    with dw.begin() as con:
        con.execute(text("TRUNCATE TABLE dq_antes_depois"))
        comparacao.to_sql("dq_antes_depois", con, if_exists="append", index=False)

    pd.set_option("display.float_format", "{:,.2f}".format)
    print(comparacao[comparacao["recorte"] == "Total"]
          .drop(columns=["recorte", "data_execucao"]).to_string(index=False))
    print()
    print(comparacao[comparacao["indicador"] == "receita_rs"]
          .drop(columns=["indicador", "data_execucao"]).to_string(index=False))


if __name__ == "__main__":
    main()
