"""Roda o trabalho inteiro, do zero, na ordem certa.

    python python/rodar_tudo.py

Faz o mesmo que os 9 passos do README, um atrás do outro. Os arquivos .sql
são executados pela própria conexão do Python, então não precisa do
programa "mysql" na linha de comando.

ATENÇÃO: apaga e recria os bancos campo_real_energia e dw_campo_real.
"""

import subprocess
import sys
import time

import pandas as pd
import pymysql
from pymysql.constants import CLIENT

from banco import PASTA_PROJETO, conectar, ler_config

PASSOS = [
    "sql/01_origem_criar.sql",       # banco de origem (passos 0 a 4.4)
    "sql/02_tabelas_extracao.sql",   # view do PLD, tabelas do clima e log
    "python/01_extrair_pld.py",      # PLD da CCEE
    "sql/03_origem_problemas.sql",   # problemas de qualidade (passo 5)
    "python/02_extrair_clima.py",    # clima da Open-Meteo
    "sql/04_dw_criar.sql",           # DDL do data warehouse
    "python/03_qualidade.py",        # profiling e métricas de qualidade
    "sql/05_dw_carga.sql",           # limpeza e carga do DW
    "python/04_antes_depois.py",     # antes x depois da limpeza
]


def rodar_sql(config, arquivo):
    """Executa um arquivo .sql inteiro (vários comandos de uma vez)."""
    b = config["banco"]
    conexao = pymysql.connect(host=b["host"], port=int(b["porta"]), user=b["usuario"],
                              password=b["senha"], charset="utf8mb4", autocommit=True,
                              client_flag=CLIENT.MULTI_STATEMENTS)
    try:
        with conexao.cursor() as cursor:
            cursor.execute((PASTA_PROJETO / arquivo).read_text(encoding="utf-8"))
            while cursor.nextset():      # passa por todos os comandos do arquivo
                pass
    finally:
        conexao.close()


def rodar_python(arquivo):
    """Executa um script Python e para tudo se ele der erro."""
    subprocess.run([sys.executable, str(PASTA_PROJETO / arquivo)], check=True)


def main():
    config = ler_config()
    inicio = time.time()

    for numero, passo in enumerate(PASSOS, start=1):
        print(f"\n===== Passo {numero} de {len(PASSOS)}: {passo} =====", flush=True)
        if passo.endswith(".sql"):
            rodar_sql(config, passo)
            print("ok")
        else:
            rodar_python(passo)

    # conferência final, lendo do DW
    dw = conectar(config, "banco_dw")
    linhas = pd.read_sql(
        "SELECT 'fato_geracao' AS tabela, COUNT(*) AS linhas FROM fato_geracao "
        "UNION ALL SELECT 'fato_pld', COUNT(*) FROM fato_pld "
        "UNION ALL SELECT 'fato_clima', COUNT(*) FROM fato_clima "
        "UNION ALL SELECT 'quarentena_medicao', COUNT(*) FROM quarentena_medicao "
        "UNION ALL SELECT 'dq_metricas', COUNT(*) FROM dq_metricas", dw)
    total = pd.read_sql(
        "SELECT ROUND(SUM(energia_mwh)) AS geracao_mwh, ROUND(SUM(receita_rs), 2) AS receita_rs "
        "FROM fato_geracao WHERE sk_usina <> -1", dw)

    print("\n===== Conferência =====")
    print(linhas.to_string(index=False))
    print(f"\nGeração 2025: {total['geracao_mwh'][0]:,.0f} MWh (esperado 3,118,741)")
    print(f"Receita 2025: R$ {total['receita_rs'][0]:,.2f} (esperado 637,819,881.98)")
    print(f"\nTerminou em {time.time() - inicio:.0f} segundos.")


if __name__ == "__main__":
    main()
