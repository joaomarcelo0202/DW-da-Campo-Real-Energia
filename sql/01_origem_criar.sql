/* =====================================================================
   01 - BANCO DE ORIGEM (parte 1: passos 0 a 4.4 do script da professora)
   ---------------------------------------------------------------------
   Este arquivo é o campo_real_energia.sql original (ver
   00_campo_real_energia_original.sql) com DUAS adaptações para rodar no
   MariaDB 10.4 do XAMPP, que foi o servidor que usamos:

     1. COLLATE utf8mb4_0900_ai_ci  ->  utf8mb4_general_ci
        (a collation 0900 só existe no MySQL 8)
     2. SET SESSION cte_max_recursion_depth  ->  comentado
        (essa variável só existe no MySQL 8; no MariaDB o limite padrão
         de recursão já é suficiente para as 8.760 horas)

   Também tiramos daqui o LOAD DATA do passo 4.5 a 4.7, porque o enunciado
   pede que a carga do PLD seja feita em Python (python/01_extrair_pld.py).
   O passo 5 (problemas de qualidade) ficou no arquivo 03, porque ele tem
   que rodar DEPOIS da carga do PLD.

   Nenhum dado foi alterado: os valores gerados são os mesmos do original.
   ===================================================================== */

/* =====================================================================
   PASSO 0 - Criar o banco
   ATENÇÃO: o DROP apaga tudo. Rodar o script inteiro de novo recria
   o banco do zero com os mesmos dados (os dados fake são determinísticos).
   ===================================================================== */
DROP DATABASE IF EXISTS campo_real_energia;

CREATE DATABASE campo_real_energia
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;

USE campo_real_energia;


/* =====================================================================
   PASSO 1 - Tabelas de cadastro
   ===================================================================== */

-- 1.1 Submercados do SIN (chave natural = código usado pela CCEE)
CREATE TABLE submercado (
    cod_submercado  CHAR(2)      NOT NULL,
    nome            VARCHAR(40)  NOT NULL,
    regioes         VARCHAR(80)  NOT NULL,
    PRIMARY KEY (cod_submercado)
);

INSERT INTO submercado (cod_submercado, nome, regioes) VALUES
  ('SE', 'Sudeste/Centro-Oeste', 'Sudeste e Centro-Oeste'),
  ('S',  'Sul',                  'Sul'),
  ('NE', 'Nordeste',             'Nordeste'),
  ('N',  'Norte',                'Norte');


-- 1.2 Fontes de energia
CREATE TABLE fonte_energia (
    id_fonte        TINYINT      NOT NULL AUTO_INCREMENT,
    cod_fonte       VARCHAR(10)  NOT NULL,
    descricao       VARCHAR(40)  NOT NULL,
    renovavel       BOOLEAN      NOT NULL,
    intermitente    BOOLEAN      NOT NULL,   -- depende de sol/vento
    PRIMARY KEY (id_fonte),
    UNIQUE KEY uk_fonte_cod (cod_fonte)
);

INSERT INTO fonte_energia (cod_fonte, descricao, renovavel, intermitente) VALUES
  ('UHE', 'Hidrelétrica',              TRUE,  FALSE),
  ('PCH', 'Pequena Central Hidrelétrica', TRUE,  FALSE),
  ('UFV', 'Solar fotovoltaica',        TRUE,  TRUE),
  ('EOL', 'Eólica',                    TRUE,  TRUE),
  ('BIO', 'Biomassa (bagaço de cana)', TRUE,  FALSE),
  ('UTE', 'Térmica a gás natural',     FALSE, FALSE);


-- 1.3 Usinas da Campo Real Energia (empresa fictícia)
CREATE TABLE usina (
    id_usina             INT           NOT NULL AUTO_INCREMENT,
    cod_usina            VARCHAR(12)   NOT NULL,      -- chave de negócio
    nome                 VARCHAR(80)   NOT NULL,
    id_fonte             TINYINT       NOT NULL,
    cod_submercado       CHAR(2)       NOT NULL,
    uf                   CHAR(2)       NOT NULL,
    municipio            VARCHAR(60)   NOT NULL,
    latitude             DECIMAL(9,6)  NOT NULL,
    longitude            DECIMAL(9,6)  NOT NULL,
    potencia_mw          DECIMAL(8,2)  NOT NULL,      -- potência instalada
    data_inicio_operacao DATE          NOT NULL,
    situacao             VARCHAR(20)   NOT NULL DEFAULT 'Em operação',
    PRIMARY KEY (id_usina),
    UNIQUE KEY uk_usina_cod (cod_usina),
    CONSTRAINT fk_usina_fonte      FOREIGN KEY (id_fonte)       REFERENCES fonte_energia (id_fonte),
    CONSTRAINT fk_usina_submercado FOREIGN KEY (cod_submercado) REFERENCES submercado (cod_submercado)
);

INSERT INTO usina (cod_usina, nome, id_fonte, cod_submercado, uf, municipio,
                   latitude, longitude, potencia_mw, data_inicio_operacao)
SELECT u.cod_usina, u.nome, f.id_fonte, u.sub, u.uf, u.municipio,
       u.lat, u.lon, u.mw, u.inicio
FROM (
  SELECT 'CRE-UHE-001' AS cod_usina, 'UHE Campo Real Iguaçu'    AS nome, 'UHE' AS fonte, 'S'  AS sub, 'PR' AS uf, 'Capitão Leônidas Marques' AS municipio, -25.4800 AS lat, -53.6100 AS lon, 180.00 AS mw, DATE '2009-03-01' AS inicio
  UNION ALL SELECT 'CRE-PCH-002', 'PCH Rio das Araucárias',  'PCH', 'S',  'SC', 'Caçador',          -26.7750, -51.0150,  25.00, DATE '2014-08-15'
  UNION ALL SELECT 'CRE-EOL-003', 'EOL Coxilha Real',        'EOL', 'S',  'RS', 'Santana do Livramento', -30.8900, -55.5300,  50.00, DATE '2016-11-01'
  UNION ALL SELECT 'CRE-UFV-004', 'UFV Campo Real Minas',    'UFV', 'SE', 'MG', 'Janaúba',          -15.8030, -43.3080,  60.00, DATE '2020-06-01'
  UNION ALL SELECT 'CRE-BIO-005', 'UTE Bagaço Campo Real',   'BIO', 'SE', 'SP', 'Sertãozinho',      -21.1380, -47.9900,  40.00, DATE '2012-04-01'
  UNION ALL SELECT 'CRE-UFV-006', 'UFV Sertão do Sol',       'UFV', 'NE', 'BA', 'Bom Jesus da Lapa', -13.2550, -43.4180,  90.00, DATE '2019-02-01'
  UNION ALL SELECT 'CRE-EOL-007', 'EOL Ventos do Potiguar',  'EOL', 'NE', 'RN', 'João Câmara',       -5.5370, -35.8190, 120.00, DATE '2015-09-01'
  UNION ALL SELECT 'CRE-UHE-008', 'UHE Tocantins Real',      'UHE', 'N',  'TO', 'Peixe',            -12.0250, -48.5400, 110.00, DATE '2006-05-01'
  UNION ALL SELECT 'CRE-UTE-009', 'UTE Gás Norte',           'UTE', 'N',  'MA', 'Santo Antônio dos Lopes', -4.8670, -44.3600, 150.00, DATE '2013-01-01'
) AS u
JOIN fonte_energia f ON f.cod_fonte = u.fonte;


-- 1.4 Feriados nacionais de 2025 (insumo para a futura dimensão de tempo)
CREATE TABLE feriado_nacional (
    data        DATE         NOT NULL,
    descricao   VARCHAR(60)  NOT NULL,
    tipo        VARCHAR(20)  NOT NULL,   -- 'Feriado' ou 'Ponto facultativo'
    PRIMARY KEY (data)
);

INSERT INTO feriado_nacional (data, descricao, tipo) VALUES
  ('2025-01-01', 'Confraternização Universal',  'Feriado'),
  ('2025-03-03', 'Carnaval',                    'Ponto facultativo'),
  ('2025-03-04', 'Carnaval',                    'Ponto facultativo'),
  ('2025-04-18', 'Sexta-feira Santa',           'Feriado'),
  ('2025-04-21', 'Tiradentes',                  'Feriado'),
  ('2025-05-01', 'Dia do Trabalho',             'Feriado'),
  ('2025-06-19', 'Corpus Christi',              'Ponto facultativo'),
  ('2025-09-07', 'Independência do Brasil',     'Feriado'),
  ('2025-10-12', 'Nossa Senhora Aparecida',     'Feriado'),
  ('2025-11-02', 'Finados',                     'Feriado'),
  ('2025-11-15', 'Proclamação da República',    'Feriado'),
  ('2025-11-20', 'Dia da Consciência Negra',    'Feriado'),
  ('2025-12-25', 'Natal',                       'Feriado');


/* =====================================================================
   PASSO 2 - Tabelas de operação
   ===================================================================== */

-- 2.1 Paradas das usinas (manutenção programada e falhas)
CREATE TABLE parada_usina (
    id_parada    INT          NOT NULL AUTO_INCREMENT,
    id_usina     INT          NOT NULL,
    inicio       DATETIME     NOT NULL,
    fim          DATETIME     NOT NULL,
    tipo         VARCHAR(20)  NOT NULL,   -- 'Programada' ou 'Forçada'
    motivo       VARCHAR(120) NOT NULL,
    PRIMARY KEY (id_parada),
    CONSTRAINT fk_parada_usina FOREIGN KEY (id_usina) REFERENCES usina (id_usina)
);

INSERT INTO parada_usina (id_usina, inicio, fim, tipo, motivo)
SELECT u.id_usina, p.inicio, p.fim, p.tipo, p.motivo
FROM (
  SELECT 'CRE-UHE-001' AS cod, TIMESTAMP '2025-07-07 00:00:00' AS inicio, TIMESTAMP '2025-07-13 23:00:00' AS fim, 'Programada' AS tipo, 'Revisão geral da unidade geradora 1' AS motivo
  UNION ALL SELECT 'CRE-PCH-002', '2025-03-10 08:00:00', '2025-03-11 17:00:00', 'Forçada',    'Falha no regulador de velocidade'
  UNION ALL SELECT 'CRE-EOL-003', '2025-05-20 00:00:00', '2025-05-22 23:00:00', 'Programada', 'Troca de caixa multiplicadora'
  UNION ALL SELECT 'CRE-UFV-004', '2025-02-14 13:00:00', '2025-02-14 18:00:00', 'Forçada',    'Desarme do inversor central após descarga atmosférica'
  UNION ALL SELECT 'CRE-BIO-005', '2025-12-01 00:00:00', '2025-12-31 23:00:00', 'Programada', 'Entressafra: manutenção da caldeira'
  UNION ALL SELECT 'CRE-UFV-006', '2025-10-02 09:00:00', '2025-10-03 16:00:00', 'Forçada',    'Falha no transformador elevador'
  UNION ALL SELECT 'CRE-EOL-007', '2025-04-14 00:00:00', '2025-04-17 23:00:00', 'Programada', 'Inspeção de pás'
  UNION ALL SELECT 'CRE-EOL-007', '2025-09-08 05:00:00', '2025-09-08 20:00:00', 'Forçada',    'Restrição de transmissão (constrained-off)'
  UNION ALL SELECT 'CRE-UHE-008', '2025-08-18 00:00:00', '2025-08-24 23:00:00', 'Programada', 'Manutenção da comporta do vertedouro'
  UNION ALL SELECT 'CRE-UTE-009', '2025-06-02 00:00:00', '2025-06-15 23:00:00', 'Programada', 'Overhaul da turbina a gás'
) AS p
JOIN usina u ON u.cod_usina = p.cod;


-- 2.2 Medição horária de geração (grão esperado: 1 usina x 1 hora)
--     Esta tabela imita a exportação do sistema de medição (SCADA), que
--     NÃO tem chave única, nem chave estrangeira, nem NOT NULL na energia.
--     Ou seja: o banco não protege nada. Garantir a qualidade é com vocês.
CREATE TABLE medicao_geracao (
    id_medicao        BIGINT        NOT NULL AUTO_INCREMENT,
    id_usina          INT,
    data_hora         DATETIME,                 -- início da hora, horário de Brasília
    energia_mwh       DECIMAL(12,3),            -- energia gerada na hora
    disponibilidade_mw DECIMAL(8,2),            -- potência disponível na hora
    origem            VARCHAR(20)   DEFAULT 'SCADA',
    recebido_em       DATETIME,                 -- quando o dado chegou ao banco
    PRIMARY KEY (id_medicao),
    KEY idx_medicao_usina_data (id_usina, data_hora),
    KEY idx_medicao_data (data_hora)
);


/* =====================================================================
   PASSO 3 - Gerar a geração horária FAKE de 2025
   ---------------------------------------------------------------------
   Lógica (simplificada, mas com comportamento realista):
     - Solar  : só gera entre 6h e 18h, curva em sino, com nuvens aleatórias
     - Eólica : mais vento no 2º semestre e à noite (forte no Nordeste)
     - Hídrica: mais água no período úmido (dez-abr), pico no fim da tarde
     - Biomassa: só na safra da cana (abr-nov)
     - Gás     : despacha no horário de ponta e na seca (ago-nov)
   O "ruído" usa CRC32, então o resultado é sempre o mesmo em qualquer
   computador (reprodutível).
   ===================================================================== */

-- 3.1 Tabela auxiliar com as 8.760 horas do ano
-- SET SESSION cte_max_recursion_depth = 10000;   -- só MySQL 8 (ver cabeçalho)

CREATE TEMPORARY TABLE tmp_horas (data_hora DATETIME PRIMARY KEY);

INSERT INTO tmp_horas (data_hora)
WITH RECURSIVE horas AS (
    SELECT TIMESTAMP '2025-01-01 00:00:00' AS data_hora
    UNION ALL
    SELECT data_hora + INTERVAL 1 HOUR
    FROM horas
    WHERE data_hora < TIMESTAMP '2025-12-31 23:00:00'
)
SELECT data_hora FROM horas;

SELECT COUNT(*) AS total_horas FROM tmp_horas;   -- esperado: 8760


-- 3.2 Calcular o fator de capacidade de cada usina em cada hora
INSERT INTO medicao_geracao (id_usina, data_hora, energia_mwh, disponibilidade_mw, recebido_em)
SELECT
    b.id_usina,
    b.data_hora,
    ROUND(b.potencia_mw * GREATEST(0, LEAST(0.98,
        CASE b.cod_fonte
          WHEN 'UFV' THEN
               GREATEST(0, SIN(PI() * (b.h - 6) / 12))                 -- curva do sol
             * (1 + 0.08 * COS(2 * PI() * (b.doy - 15) / 365))         -- mais forte no verão
             * (0.55 + 0.45 * b.ruido)                                 -- nuvens
             * 0.88
          WHEN 'EOL' THEN
               (CASE b.cod_submercado WHEN 'NE' THEN 0.30 ELSE 0.22 END)
             + (CASE b.cod_submercado WHEN 'NE' THEN 0.35 ELSE 0.18 END)
               * (1 + COS(2 * PI() * (b.doy - 242) / 365)) / 2         -- safra de ventos (ago-set)
             + 0.12 * COS(2 * PI() * (b.h - 2) / 24)                   -- venta mais de madrugada
             + 0.35 * (b.ruido - 0.5)
          WHEN 'UHE' THEN
               (CASE b.cod_submercado WHEN 'S' THEN 0.58 ELSE 0.52 END)
             + (CASE b.cod_submercado WHEN 'S' THEN 0.08 ELSE 0.25 END)
               * COS(2 * PI() * (b.doy - 45) / 365)                    -- período úmido
             + 0.10 * SIN(PI() * (b.h - 6) / 18) * (b.h BETWEEN 6 AND 23)  -- acompanha a carga
             + 0.08 * (b.ruido - 0.5)
          WHEN 'PCH' THEN
               0.60 + 0.15 * COS(2 * PI() * (b.doy - 30) / 365)
             + 0.10 * (b.ruido - 0.5)
          WHEN 'BIO' THEN
               CASE WHEN b.mes BETWEEN 4 AND 11
                    THEN 0.78 + 0.15 * (b.ruido - 0.5)
                    ELSE 0.02 + 0.03 * b.ruido END
          WHEN 'UTE' THEN
               CASE WHEN b.h BETWEEN 17 AND 21 AND b.ruido > 0.25 THEN 0.84 + 0.08 * b.ruido
                    WHEN b.mes BETWEEN 8 AND 11 AND b.ruido > 0.40 THEN 0.76 + 0.08 * b.ruido
                    WHEN b.ruido > 0.93                         THEN 0.60 + 0.05 * b.ruido
                    ELSE 0 END
        END
    )), 3) AS energia_mwh,
    b.potencia_mw AS disponibilidade_mw,
    b.data_hora + INTERVAL (65 + FLOOR(b.ruido * 40)) MINUTE AS recebido_em   -- chega ~1h depois
FROM (
    SELECT u.id_usina, u.potencia_mw, u.cod_submercado, f.cod_fonte,
           t.data_hora,
           HOUR(t.data_hora)      AS h,
           MONTH(t.data_hora)     AS mes,
           DAYOFYEAR(t.data_hora) AS doy,
           (CRC32(CONCAT(u.cod_usina, '|', t.data_hora)) % 10000) / 10000 AS ruido
    FROM usina u
    JOIN fonte_energia f ON f.id_fonte = u.id_fonte
    CROSS JOIN tmp_horas t
) AS b;

DROP TEMPORARY TABLE tmp_horas;


-- 3.3 Zerar a geração e a disponibilidade nas horas de parada
UPDATE medicao_geracao m
JOIN parada_usina p
  ON p.id_usina = m.id_usina
 AND m.data_hora BETWEEN p.inicio AND p.fim
SET m.energia_mwh        = 0,
    m.disponibilidade_mw = 0;


-- 3.4 Conferência
SELECT u.cod_usina, u.nome,
       COUNT(*)                                   AS horas,          -- esperado: 8760
       ROUND(SUM(m.energia_mwh) / 1000, 1)        AS gwh_ano,
       ROUND(SUM(m.energia_mwh) / (u.potencia_mw * 8760) * 100, 1) AS fator_capacidade_pct
FROM medicao_geracao m
JOIN usina u ON u.id_usina = m.id_usina
GROUP BY u.id_usina, u.cod_usina, u.nome, u.potencia_mw
ORDER BY u.id_usina;


/* =====================================================================
   PASSO 4 - Extração do PLD horário REAL (CCEE)
   ---------------------------------------------------------------------
   4.1 Baixe o CSV de 2025 em:
       https://dadosabertos.ccee.org.br/dataset/pld_horario
       -> recurso "pld_horario_2025" -> Baixar -> CSV
       Link direto do CSV do portal (CKAN):
       https://dadosabertos.ccee.org.br/datastore/dump/2a180a6b-f092-43eb-9f82-a48798b803dc

   Colunas segundo o dicionário de dados da CCEE:
       MES_REFERENCIA (AAAAMM), SUBMERCADO, PERIODO_COMERCIALIZACAO,
       DIA (DD/MM/AAAA), HORA, PLD_HORA (R$/MWh)
   O CSV do link direto vem com uma coluna extra "_id" no começo.

   ABRA O ARQUIVO NUM EDITOR DE TEXTO ANTES DE CARREGAR e confira:
     - o separador (vírgula ou ponto e vírgula)
     - se existe a coluna _id
     - o formato da data e do número
   Isso é parte do trabalho de engenharia de dados.
   ===================================================================== */

-- 4.2 Staging: guarda o CSV exatamente como veio (tudo texto)
CREATE TABLE stg_pld_horario (
    id_ckan                 VARCHAR(20),
    mes_referencia          VARCHAR(10),
    submercado              VARCHAR(40),
    periodo_comercializacao VARCHAR(10),
    dia                     VARCHAR(30),
    hora                    VARCHAR(10),
    pld_hora                VARCHAR(30),
    arquivo_origem          VARCHAR(100),
    carregado_em            DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 4.3 Tabela tratada do PLD (grão: 1 submercado x 1 hora)
CREATE TABLE pld_horario (
    cod_submercado          CHAR(2)        NOT NULL,
    data_hora               DATETIME       NOT NULL,   -- início da hora, horário de Brasília
    mes_referencia          CHAR(6)        NOT NULL,
    periodo_comercializacao SMALLINT       NOT NULL,
    pld_rs_mwh              DECIMAL(10,2)  NOT NULL,
    origem                  VARCHAR(20)    NOT NULL,   -- 'CCEE' ou 'SIMULADO'
    PRIMARY KEY (cod_submercado, data_hora),
    CONSTRAINT fk_pld_submercado FOREIGN KEY (cod_submercado) REFERENCES submercado (cod_submercado)
);

-- 4.4 Log de cargas
CREATE TABLE log_carga (
    id_log        INT          NOT NULL AUTO_INCREMENT,
    tabela        VARCHAR(40)  NOT NULL,
    arquivo       VARCHAR(100),
    linhas        INT,
    status        VARCHAR(20)  NOT NULL,
    observacao    VARCHAR(255),
    registrado_em DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_log)
);
