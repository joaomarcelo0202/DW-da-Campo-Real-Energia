"""Funções que todos os scripts usam: ler o config.ini, conectar no banco
e gravar o log das execuções."""

import configparser
from datetime import datetime
from pathlib import Path

from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

# pasta raiz do projeto (a pasta acima de /python)
PASTA_PROJETO = Path(__file__).resolve().parent.parent


def ler_config():
    """Lê o config.ini que fica na raiz do projeto."""
    arquivo = PASTA_PROJETO / "config.ini"
    if not arquivo.exists():
        raise SystemExit("Não achei o config.ini. Copie o config.exemplo.ini para config.ini.")
    config = configparser.ConfigParser()
    config.read(arquivo, encoding="utf-8")
    return config


def conectar(config, qual="banco_origem"):
    """Devolve a conexão (engine) com o banco de origem ou com o DW."""
    b = config["banco"]
    url = URL.create(
        "mysql+pymysql",
        username=b["usuario"],
        password=b["senha"] or None,
        host=b["host"],
        port=int(b["porta"]),
        database=b[qual],
        query={"charset": "utf8mb4"},
    )
    return create_engine(url)


def iniciar_log(engine, processo, fonte):
    """Grava o início de uma execução e devolve o id do log."""
    with engine.begin() as con:
        resultado = con.execute(
            text("INSERT INTO log_extracao (processo, fonte, inicio, status) "
                 "VALUES (:processo, :fonte, :inicio, 'EXECUTANDO')"),
            {"processo": processo, "fonte": fonte, "inicio": datetime.now()},
        )
        return resultado.lastrowid


def finalizar_log(engine, id_log, status, lidas=0, gravadas=0, erro=None):
    """Fecha o log com o fim, as contagens, o status e o erro (se teve)."""
    with engine.begin() as con:
        con.execute(
            text("UPDATE log_extracao SET fim = :fim, linhas_lidas = :lidas, "
                 "linhas_gravadas = :gravadas, status = :status, erro = :erro "
                 "WHERE id_log = :id_log"),
            {"fim": datetime.now(), "lidas": lidas, "gravadas": gravadas,
             "status": status, "erro": str(erro)[:500] if erro else None,
             "id_log": id_log},
        )
