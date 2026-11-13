/* =====================================================================
   04 - DATA WAREHOUSE: criação das tabelas (DDL)
   ---------------------------------------------------------------------
   Schema separado: dw_campo_real

   Dimensões
     dim_tempo       1 linha por hora (2025 e 2026)
     dim_submercado  1 linha por submercado
     dim_usina       1 linha por versão da usina (SCD tipo 2), já com a
                     fonte de energia e o nome do submercado dentro
     dim_parada      1 linha por parada + a linha 0 = "Sem parada"

   Fatos (grão)
     fato_geracao    1 usina x 1 hora
     fato_pld        1 submercado x 1 hora
     fato_clima      1 usina x 1 hora

   Membro "desconhecido": chave -1 em dim_usina e dim_submercado.

   Apoio
     stg_medicao_limpa, stg_pld_limpo   dados já limpos, antes dos fatos
     quarentena_medicao                 medições descartadas e o motivo
     dq_profiling, dq_metricas, dq_antes_depois   qualidade de dados

   ATENÇÃO: o DROP apaga o DW inteiro (inclusive as métricas de qualidade).
   ===================================================================== */

DROP DATABASE IF EXISTS dw_campo_real;

CREATE DATABASE dw_campo_real
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;

USE dw_campo_real;


/* =====================================================================
   DIMENSÕES
   ===================================================================== */

-- Tempo: grão de 1 hora. A chave é o próprio momento no formato AAAAMMDDHH.
CREATE TABLE dim_tempo (
    sk_tempo         INT          NOT NULL,   -- ex.: 2025091512
    data_hora        DATETIME     NOT NULL,
    data             DATE         NOT NULL,
    ano              SMALLINT     NOT NULL,
    mes              TINYINT      NOT NULL,
    nome_mes         VARCHAR(15)  NOT NULL,
    dia              TINYINT      NOT NULL,
    hora             TINYINT      NOT NULL,   -- 0 a 23
    dia_semana       TINYINT      NOT NULL,   -- 1 = domingo ... 7 = sábado
    nome_dia_semana  VARCHAR(15)  NOT NULL,
    fim_de_semana    TINYINT      NOT NULL,   -- 1 = sábado ou domingo
    feriado          TINYINT      NOT NULL,   -- 1 = feriado ou ponto facultativo
    nome_feriado     VARCHAR(60),
    dia_util         TINYINT      NOT NULL,   -- 1 = segunda a sexta e não é feriado
    estacao_ano      VARCHAR(10)  NOT NULL,   -- Verão, Outono, Inverno, Primavera
    patamar_carga    VARCHAR(10)  NOT NULL,   -- Leve, Média, Pesada
    PRIMARY KEY (sk_tempo),
    UNIQUE KEY uk_tempo_data_hora (data_hora)
);

CREATE TABLE dim_submercado (
    sk_submercado   INT          NOT NULL AUTO_INCREMENT,
    cod_submercado  VARCHAR(3)   NOT NULL,    -- chave natural (CCEE)
    nome            VARCHAR(40)  NOT NULL,
    regioes         VARCHAR(80)  NOT NULL,
    PRIMARY KEY (sk_submercado),
    UNIQUE KEY uk_submercado_cod (cod_submercado)
);

-- Usina: SCD tipo 2 (uma linha nova a cada mudança de nome, potência ou situação)
CREATE TABLE dim_usina (
    sk_usina             INT           NOT NULL AUTO_INCREMENT,
    cod_usina            VARCHAR(12)   NOT NULL,   -- chave natural (de negócio)
    nome                 VARCHAR(80)   NOT NULL,
    cod_fonte            VARCHAR(10)   NOT NULL,
    fonte                VARCHAR(40)   NOT NULL,
    renovavel            VARCHAR(3)    NOT NULL,   -- Sim / Não / N/D
    intermitente         VARCHAR(3)    NOT NULL,   -- Sim / Não / N/D
    cod_submercado       VARCHAR(3)    NOT NULL,
    submercado           VARCHAR(40)   NOT NULL,
    uf                   CHAR(2)       NOT NULL,
    municipio            VARCHAR(60)   NOT NULL,
    latitude             DECIMAL(9,6),
    longitude            DECIMAL(9,6),
    potencia_mw          DECIMAL(8,2),
    data_inicio_operacao DATE,                     -- NULL = não confiável na origem
    situacao             VARCHAR(20)   NOT NULL,
    vigencia_inicio      DATE          NOT NULL,   -- controle do SCD 2
    vigencia_fim         DATE          NOT NULL,
    registro_atual       TINYINT       NOT NULL,   -- 1 = versão que vale hoje
    PRIMARY KEY (sk_usina),
    KEY idx_usina_cod (cod_usina)
);

-- Parada: a linha 0 é "Sem parada" (toda hora normal aponta para ela)
CREATE TABLE dim_parada (
    sk_parada      INT          NOT NULL,
    id_parada      INT,                      -- id na tabela de origem
    cod_usina      VARCHAR(12),
    tipo_parada    VARCHAR(20)  NOT NULL,    -- Programada, Forçada, Sem parada
    motivo         VARCHAR(120) NOT NULL,
    inicio         DATETIME,
    fim            DATETIME,
    duracao_horas  INT,
    PRIMARY KEY (sk_parada)
);


/* =====================================================================
   FATOS
   ===================================================================== */

-- Grão: 1 usina x 1 hora
CREATE TABLE fato_geracao (
    id_medicao           BIGINT        NOT NULL,   -- dimensão degenerada (rastreia a origem)
    sk_tempo             INT           NOT NULL,
    sk_usina             INT           NOT NULL,
    sk_submercado        INT           NOT NULL,
    sk_parada            INT           NOT NULL,
    energia_mwh          DECIMAL(12,3),            -- NULL = sem leitura confiável
    disponibilidade_mw   DECIMAL(8,2),
    capacidade_mwh       DECIMAL(8,2),             -- potência instalada x 1 hora
    pld_rs_mwh           DECIMAL(10,2),            -- PLD da hora no submercado da usina
    receita_rs           DECIMAL(14,2),            -- energia x PLD
    energia_perdida_mwh  DECIMAL(12,3) NOT NULL DEFAULT 0,   -- estimativa nas horas de parada
    receita_perdida_rs   DECIMAL(14,2) NOT NULL DEFAULT 0,
    flag_qualidade       VARCHAR(25)   NOT NULL,
    flag_atualidade      VARCHAR(20)   NOT NULL,
    PRIMARY KEY (id_medicao),
    KEY idx_fg_tempo (sk_tempo),
    KEY idx_fg_usina (sk_usina),
    CONSTRAINT fk_fg_tempo      FOREIGN KEY (sk_tempo)      REFERENCES dim_tempo (sk_tempo),
    CONSTRAINT fk_fg_usina      FOREIGN KEY (sk_usina)      REFERENCES dim_usina (sk_usina),
    CONSTRAINT fk_fg_submercado FOREIGN KEY (sk_submercado) REFERENCES dim_submercado (sk_submercado),
    CONSTRAINT fk_fg_parada     FOREIGN KEY (sk_parada)     REFERENCES dim_parada (sk_parada)
);

-- Grão: 1 submercado x 1 hora
CREATE TABLE fato_pld (
    sk_tempo        INT            NOT NULL,
    sk_submercado   INT            NOT NULL,
    pld_rs_mwh      DECIMAL(10,2)  NOT NULL,
    flag_qualidade  VARCHAR(25)    NOT NULL,
    PRIMARY KEY (sk_tempo, sk_submercado),
    CONSTRAINT fk_fp_tempo      FOREIGN KEY (sk_tempo)      REFERENCES dim_tempo (sk_tempo),
    CONSTRAINT fk_fp_submercado FOREIGN KEY (sk_submercado) REFERENCES dim_submercado (sk_submercado)
);

-- Grão: 1 usina x 1 hora (clima no ponto da usina, fonte Open-Meteo)
CREATE TABLE fato_clima (
    sk_tempo       INT          NOT NULL,
    sk_usina       INT          NOT NULL,
    temperatura_c  DECIMAL(5,1),
    radiacao_wm2   DECIMAL(7,1),
    vento_kmh      DECIMAL(6,1),
    chuva_mm       DECIMAL(6,1),
    PRIMARY KEY (sk_tempo, sk_usina),
    CONSTRAINT fk_fc_tempo FOREIGN KEY (sk_tempo) REFERENCES dim_tempo (sk_tempo),
    CONSTRAINT fk_fc_usina FOREIGN KEY (sk_usina) REFERENCES dim_usina (sk_usina)
);


/* =====================================================================
   TABELAS DE APOIO (limpeza)
   ===================================================================== */

-- Medições aprovadas (com as correções aplicadas)
CREATE TABLE stg_medicao_limpa (
    id_medicao            BIGINT        NOT NULL,
    id_usina              INT,
    cod_usina             VARCHAR(12),              -- NULL = usina não está no cadastro
    cod_fonte             VARCHAR(10),
    potencia_mw           DECIMAL(8,2),
    data_hora             DATETIME      NOT NULL,
    energia_mwh           DECIMAL(12,3),            -- valor depois da limpeza
    energia_original_mwh  DECIMAL(12,3),            -- valor como estava na origem
    disponibilidade_mw    DECIMAL(8,2),
    origem                VARCHAR(20),
    recebido_em           DATETIME,
    flag_qualidade        VARCHAR(25)   NOT NULL DEFAULT 'OK',
    flag_atualidade       VARCHAR(20)   NOT NULL DEFAULT 'NO_PRAZO',
    PRIMARY KEY (id_medicao),
    KEY idx_sml_usina_data (cod_usina, data_hora)
);

-- Medições que não entram no DW (ficam guardadas com o motivo)
CREATE TABLE quarentena_medicao (
    id_medicao          BIGINT        NOT NULL,
    id_usina            INT,
    data_hora           DATETIME,
    energia_mwh         DECIMAL(12,3),
    disponibilidade_mw  DECIMAL(8,2),
    origem              VARCHAR(20),
    recebido_em         DATETIME,
    motivo              VARCHAR(40)   NOT NULL,
    PRIMARY KEY (id_medicao)
);

-- PLD aprovado
CREATE TABLE stg_pld_limpo (
    cod_submercado  VARCHAR(3)     NOT NULL,
    data_hora       DATETIME       NOT NULL,
    pld_rs_mwh      DECIMAL(10,2)  NOT NULL,
    flag_qualidade  VARCHAR(25)    NOT NULL,
    PRIMARY KEY (cod_submercado, data_hora)
);


/* =====================================================================
   QUALIDADE DE DADOS (gravadas pelos scripts Python)
   ===================================================================== */

CREATE TABLE dq_profiling (
    id_profiling   INT          NOT NULL AUTO_INCREMENT,
    tabela         VARCHAR(40)  NOT NULL,
    coluna         VARCHAR(40)  NOT NULL,
    tipo           VARCHAR(30)  NOT NULL,
    total_linhas   INT          NOT NULL,
    nulos          INT          NOT NULL,
    distintos      INT          NOT NULL,
    minimo         VARCHAR(60),
    maximo         VARCHAR(60),
    media          DOUBLE,
    mediana        DOUBLE,
    data_execucao  DATETIME     NOT NULL,
    PRIMARY KEY (id_profiling)
);

CREATE TABLE dq_metricas (
    id_metrica           INT           NOT NULL AUTO_INCREMENT,
    regra                VARCHAR(120)  NOT NULL,
    dimensao             VARCHAR(30)   NOT NULL,
    tabela               VARCHAR(40)   NOT NULL,
    registros_avaliados  INT           NOT NULL,
    registros_falha      INT           NOT NULL,
    percentual_falha     DECIMAL(8,4)  NOT NULL,
    decisao              VARCHAR(255)  NOT NULL,
    data_execucao        DATETIME      NOT NULL,
    PRIMARY KEY (id_metrica)
);

CREATE TABLE dq_antes_depois (
    id_comparacao   INT            NOT NULL AUTO_INCREMENT,
    indicador       VARCHAR(40)    NOT NULL,
    recorte         VARCHAR(80)    NOT NULL,   -- 'Total' ou o nome da usina
    valor_antes     DECIMAL(18,2),
    valor_depois    DECIMAL(18,2),
    diferenca       DECIMAL(18,2),
    diferenca_pct   DECIMAL(10,2),
    data_execucao   DATETIME       NOT NULL,
    PRIMARY KEY (id_comparacao)
);
