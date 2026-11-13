/* =====================================================================
   02 - TABELAS DA EXTRAÇÃO (Etapa 1)
   ---------------------------------------------------------------------
   Cria o que o grupo precisa para receber as fontes externas:

     PLD (CCEE)
       stg_pld_horario  -> camada RAW  (já criada pelo script da professora:
                           tudo texto, do jeito que veio, com arquivo de
                           origem e data/hora da carga)
       vw_pld_raw       -> view que só converte os tipos do raw
       pld_horario      -> camada TRATADA (já criada pelo script da
                           professora). Grão: 1 submercado x 1 hora.
                           Chave: (cod_submercado, data_hora)

     Clima (Open-Meteo)
       raw_clima_openmeteo -> camada RAW: o JSON inteiro que a API devolveu
       clima_horario       -> camada TRATADA. Grão: 1 usina x 1 hora.
                              Chave: (cod_usina, data_hora)

     log_extracao -> uma linha para cada execução dos scripts Python
   ===================================================================== */

USE campo_real_energia;

-- ---------------------------------------------------------------------
-- PLD: view que transforma o raw (texto) em colunas com tipo
-- No CSV da CCEE a coluna DIA traz só o dia do mês (ex.: 31) e a data
-- completa é MES_REFERENCIA (AAAAMM) + DIA. A hora vem de 0 a 23.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_pld_raw AS
SELECT
    CASE UPPER(TRIM(submercado))
        WHEN 'SUDESTE'  THEN 'SE'
        WHEN 'SUL'      THEN 'S'
        WHEN 'NORDESTE' THEN 'NE'
        WHEN 'NORTE'    THEN 'N'
    END                                                         AS cod_submercado,
    STR_TO_DATE(CONCAT(TRIM(mes_referencia), LPAD(TRIM(dia), 2, '0')), '%Y%m%d')
        + INTERVAL CAST(hora AS UNSIGNED) HOUR                  AS data_hora,
    TRIM(mes_referencia)                                        AS mes_referencia,
    CAST(periodo_comercializacao AS UNSIGNED)                   AS periodo_comercializacao,
    CAST(pld_hora AS DECIMAL(10,2))                             AS pld_rs_mwh
FROM stg_pld_horario
WHERE TRIM(pld_hora) <> '';


-- ---------------------------------------------------------------------
-- Clima: camada raw (guarda a resposta da API exatamente como chegou)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_clima_openmeteo (
    id_raw        INT          NOT NULL AUTO_INCREMENT,
    cod_usina     VARCHAR(12)  NOT NULL,
    latitude      DECIMAL(9,6) NOT NULL,
    longitude     DECIMAL(9,6) NOT NULL,
    data_inicio   DATE         NOT NULL,
    data_fim      DATE         NOT NULL,
    resposta_json LONGTEXT     NOT NULL,
    origem        VARCHAR(100) NOT NULL,
    extraido_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_raw)
);

-- Clima: camada tratada
CREATE TABLE IF NOT EXISTS clima_horario (
    cod_usina      VARCHAR(12)  NOT NULL,
    data_hora      DATETIME     NOT NULL,   -- início da hora, horário de Brasília
    temperatura_c  DECIMAL(5,1),            -- temperatura a 2 m
    radiacao_wm2   DECIMAL(7,1),            -- radiação solar de onda curta
    vento_kmh      DECIMAL(6,1),            -- vento a 100 m de altura
    chuva_mm       DECIMAL(6,1),            -- precipitação na hora
    origem         VARCHAR(20)  NOT NULL DEFAULT 'OPEN-METEO',
    PRIMARY KEY (cod_usina, data_hora)
);


-- ---------------------------------------------------------------------
-- Log das execuções da extração
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_extracao (
    id_log          INT          NOT NULL AUTO_INCREMENT,
    processo        VARCHAR(40)  NOT NULL,   -- ex.: 'PLD 2025', 'CLIMA CRE-UHE-001'
    fonte           VARCHAR(100) NOT NULL,   -- de onde veio (API, arquivo CSV...)
    inicio          DATETIME     NOT NULL,
    fim             DATETIME,
    linhas_lidas    INT,
    linhas_gravadas INT,
    status          VARCHAR(20)  NOT NULL,   -- 'EXECUTANDO', 'OK', 'ERRO', 'JA_BAIXADO'
    erro            VARCHAR(500),
    PRIMARY KEY (id_log)
);
