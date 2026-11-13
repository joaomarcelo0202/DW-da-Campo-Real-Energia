/* =====================================================================
   05 - DATA WAREHOUSE: limpeza e carga
   ---------------------------------------------------------------------
   Lê do banco de origem (campo_real_energia) e grava no DW (dw_campo_real).
   As tabelas de origem NÃO são alteradas: a limpeza acontece aqui, no
   caminho até o warehouse. Cada correção tem um comentário com a decisão
   (o relatório completo está em docs/relatorio_qualidade.md).

   Pode rodar de novo: o passo 0 esvazia as tabelas antes de carregar.

   Observação: no MySQL 8 é preciso rodar antes a linha abaixo (no MariaDB
   não precisa e a variável nem existe):
   -- SET SESSION cte_max_recursion_depth = 20000;
   ===================================================================== */

USE dw_campo_real;

SET lc_time_names = 'pt_BR';      -- nomes de mês e dia da semana em português


/* =====================================================================
   PASSO 0 - Esvaziar (fatos primeiro, depois dimensões)
   ===================================================================== */
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE fato_geracao;
TRUNCATE TABLE fato_pld;
TRUNCATE TABLE fato_clima;
TRUNCATE TABLE dim_tempo;
TRUNCATE TABLE dim_usina;
TRUNCATE TABLE dim_submercado;
TRUNCATE TABLE dim_parada;
TRUNCATE TABLE stg_medicao_limpa;
TRUNCATE TABLE stg_pld_limpo;
TRUNCATE TABLE quarentena_medicao;
SET FOREIGN_KEY_CHECKS = 1;


/* =====================================================================
   PASSO 1 - dim_submercado
   ===================================================================== */
INSERT INTO dim_submercado (sk_submercado, cod_submercado, nome, regioes)
VALUES (-1, 'N/D', 'Desconhecido', 'Desconhecido');

INSERT INTO dim_submercado (cod_submercado, nome, regioes)
SELECT cod_submercado, nome, regioes
FROM campo_real_energia.submercado
ORDER BY cod_submercado;


/* =====================================================================
   PASSO 2 - dim_usina (com a fonte e o submercado dentro)
   ---------------------------------------------------------------------
   Limpeza do cadastro:
     - cadastro duplicado (código fora do padrão CRE-XXX-999): descartado
     - nome com espaço sobrando: TRIM
     - latitude maior que 6 (fora do Brasil): sinal invertido
     - UF 'PE' na usina de Sertãozinho (submercado SE): corrigida para 'SP'
     - início de operação no futuro: vira NULL (não sabemos a data certa)
   Carga inicial do SCD 2: uma versão por usina, valendo "desde sempre".
   ===================================================================== */
INSERT INTO dim_usina (sk_usina, cod_usina, nome, cod_fonte, fonte, renovavel, intermitente,
                       cod_submercado, submercado, uf, municipio, situacao,
                       vigencia_inicio, vigencia_fim, registro_atual)
VALUES (-1, 'N/D', 'Usina desconhecida', 'N/D', 'Desconhecida', 'N/D', 'N/D',
        'N/D', 'Desconhecido', '--', 'Desconhecido', 'Desconhecida',
        '1900-01-01', '9999-12-31', 1);

INSERT INTO dim_usina (cod_usina, nome, cod_fonte, fonte, renovavel, intermitente,
                       cod_submercado, submercado, uf, municipio, latitude, longitude,
                       potencia_mw, data_inicio_operacao, situacao,
                       vigencia_inicio, vigencia_fim, registro_atual)
SELECT u.cod_usina,
       TRIM(u.nome),
       f.cod_fonte,
       f.descricao,
       IF(f.renovavel, 'Sim', 'Não'),
       IF(f.intermitente, 'Sim', 'Não'),
       s.cod_submercado,
       s.nome,
       CASE WHEN u.cod_usina = 'CRE-BIO-005' AND u.uf = 'PE' THEN 'SP' ELSE u.uf END,
       u.municipio,
       CASE WHEN u.latitude > 6 THEN -u.latitude ELSE u.latitude END,
       u.longitude,
       u.potencia_mw,
       CASE WHEN u.data_inicio_operacao > CURRENT_DATE THEN NULL ELSE u.data_inicio_operacao END,
       u.situacao,
       '1900-01-01', '9999-12-31', 1
FROM campo_real_energia.usina u
JOIN campo_real_energia.fonte_energia f ON f.id_fonte = u.id_fonte
JOIN campo_real_energia.submercado s    ON s.cod_submercado = u.cod_submercado
WHERE u.cod_usina REGEXP '^CRE-[A-Z]{3}-[0-9]{3}$'
ORDER BY u.cod_usina;


/* =====================================================================
   PASSO 3 - dim_tempo (uma linha por hora de 2025 e 2026)
   ---------------------------------------------------------------------
   Feriados: 2025 vem da tabela de origem; 2026 não existe na origem,
   então os feriados nacionais de 2026 foram listados aqui.
   Estação do ano: datas aproximadas do hemisfério sul.
   Patamar de carga (regra simplificada):
     dia útil ............ Leve 0h-6h | Média 7h-17h e 21h-23h | Pesada 18h-20h
     sáb., dom. e feriado . Leve 0h-16h e 22h-23h | Média 17h-21h
   ===================================================================== */
CREATE TEMPORARY TABLE tmp_feriado (
    data       DATE        NOT NULL PRIMARY KEY,
    descricao  VARCHAR(60) NOT NULL
);

INSERT INTO tmp_feriado (data, descricao)
SELECT data, descricao FROM campo_real_energia.feriado_nacional;

INSERT INTO tmp_feriado (data, descricao) VALUES
  ('2026-01-01', 'Confraternização Universal'),
  ('2026-02-16', 'Carnaval'),
  ('2026-02-17', 'Carnaval'),
  ('2026-04-03', 'Sexta-feira Santa'),
  ('2026-04-21', 'Tiradentes'),
  ('2026-05-01', 'Dia do Trabalho'),
  ('2026-06-04', 'Corpus Christi'),
  ('2026-09-07', 'Independência do Brasil'),
  ('2026-10-12', 'Nossa Senhora Aparecida'),
  ('2026-11-02', 'Finados'),
  ('2026-11-15', 'Proclamação da República'),
  ('2026-11-20', 'Dia da Consciência Negra'),
  ('2026-12-25', 'Natal');

INSERT INTO dim_tempo (sk_tempo, data_hora, data, ano, mes, nome_mes, dia, hora,
                       dia_semana, nome_dia_semana, fim_de_semana, feriado, nome_feriado,
                       dia_util, estacao_ano, patamar_carga)
WITH RECURSIVE horas AS (
    SELECT CAST('2025-01-01 00:00:00' AS DATETIME) AS data_hora
    UNION ALL
    SELECT data_hora + INTERVAL 1 HOUR
    FROM horas
    WHERE data_hora < '2026-12-31 23:00:00'
)
SELECT
    CAST(DATE_FORMAT(h.data_hora, '%Y%m%d%H') AS UNSIGNED),
    h.data_hora,
    DATE(h.data_hora),
    YEAR(h.data_hora),
    MONTH(h.data_hora),
    MONTHNAME(h.data_hora),
    DAY(h.data_hora),
    HOUR(h.data_hora),
    DAYOFWEEK(h.data_hora),
    DAYNAME(h.data_hora),
    IF(DAYOFWEEK(h.data_hora) IN (1, 7), 1, 0),
    IF(f.data IS NULL, 0, 1),
    f.descricao,
    IF(DAYOFWEEK(h.data_hora) IN (1, 7) OR f.data IS NOT NULL, 0, 1),
    CASE
        WHEN DATE_FORMAT(h.data_hora, '%m%d') >= '1221' OR DATE_FORMAT(h.data_hora, '%m%d') < '0321' THEN 'Verão'
        WHEN DATE_FORMAT(h.data_hora, '%m%d') < '0621' THEN 'Outono'
        WHEN DATE_FORMAT(h.data_hora, '%m%d') < '0923' THEN 'Inverno'
        ELSE 'Primavera'
    END,
    CASE
        WHEN DAYOFWEEK(h.data_hora) IN (1, 7) OR f.data IS NOT NULL THEN       -- fim de semana ou feriado
            CASE WHEN HOUR(h.data_hora) BETWEEN 17 AND 21 THEN 'Média' ELSE 'Leve' END
        ELSE                                                                   -- dia útil
            CASE WHEN HOUR(h.data_hora) <= 6              THEN 'Leve'
                 WHEN HOUR(h.data_hora) BETWEEN 18 AND 20 THEN 'Pesada'
                 ELSE 'Média' END
    END
FROM horas h
LEFT JOIN tmp_feriado f ON f.data = DATE(h.data_hora);

DROP TEMPORARY TABLE tmp_feriado;


/* =====================================================================
   PASSO 4 - dim_parada
   ---------------------------------------------------------------------
   Linha 0 = "Sem parada". A parada com fim antes do início é descartada
   (não dá para saber qual era o horário certo).
   ===================================================================== */
INSERT INTO dim_parada (sk_parada, id_parada, cod_usina, tipo_parada, motivo, inicio, fim, duracao_horas)
VALUES (0, NULL, NULL, 'Sem parada', 'Sem parada', NULL, NULL, 0);

INSERT INTO dim_parada (sk_parada, id_parada, cod_usina, tipo_parada, motivo, inicio, fim, duracao_horas)
SELECT p.id_parada, p.id_parada, u.cod_usina, p.tipo, p.motivo, p.inicio, p.fim,
       TIMESTAMPDIFF(HOUR, p.inicio, p.fim) + 1
FROM campo_real_energia.parada_usina p
JOIN campo_real_energia.usina u ON u.id_usina = p.id_usina
WHERE p.fim >= p.inicio;


/* =====================================================================
   PASSO 5 - PLD limpo
   ---------------------------------------------------------------------
   A tabela tratada (pld_horario) tem 3 problemas: um dia inteiro faltando
   no Nordeste, um preço acima do teto e um preço negativo. Como a camada
   raw guarda o dado exatamente como veio da CCEE, o PLD limpo é montado a
   partir do raw, e a coluna flag_qualidade mostra o que precisou ser
   recuperado. Só entram preços dentro dos limites da ANEEL de cada ano.
   ===================================================================== */
INSERT INTO stg_pld_limpo (cod_submercado, data_hora, pld_rs_mwh, flag_qualidade)
SELECT r.cod_submercado,
       r.data_hora,
       r.pld_rs_mwh,
       CASE WHEN p.data_hora IS NULL             THEN 'RECUPERADO_DO_RAW'
            WHEN p.pld_rs_mwh <> r.pld_rs_mwh    THEN 'CORRIGIDO_PELO_RAW'
            ELSE 'OK' END
FROM campo_real_energia.vw_pld_raw r
LEFT JOIN campo_real_energia.pld_horario p
       ON p.cod_submercado = r.cod_submercado
      AND p.data_hora      = r.data_hora
WHERE (YEAR(r.data_hora) = 2025 AND r.pld_rs_mwh BETWEEN 58.60 AND 1542.23)
   OR (YEAR(r.data_hora) = 2026 AND r.pld_rs_mwh BETWEEN 57.31 AND 1611.04);


/* =====================================================================
   PASSO 6 - Medições: quarentena
   ===================================================================== */

-- 6.1 Data fora de 2025 (ano digitado errado: 2052)
INSERT INTO quarentena_medicao
SELECT id_medicao, id_usina, data_hora, energia_mwh, disponibilidade_mw, origem, recebido_em,
       'DATA_FORA_DO_PERIODO'
FROM campo_real_energia.medicao_geracao
WHERE data_hora IS NULL OR YEAR(data_hora) <> 2025;

-- 6.2 Duplicadas: para a mesma usina e hora fica UMA leitura.
--     Preferência: leitura automática (SCADA); empatou, a que chegou primeiro.
INSERT INTO quarentena_medicao
SELECT id_medicao, id_usina, data_hora, energia_mwh, disponibilidade_mw, origem, recebido_em,
       'DUPLICADA'
FROM (
    SELECT m.*,
           ROW_NUMBER() OVER (PARTITION BY m.id_usina, m.data_hora
                              ORDER BY (m.origem = 'SCADA') DESC, m.recebido_em, m.id_medicao) AS ordem
    FROM campo_real_energia.medicao_geracao m
    WHERE YEAR(m.data_hora) = 2025
) AS x
WHERE x.ordem > 1;


/* =====================================================================
   PASSO 7 - Medições limpas
   ---------------------------------------------------------------------
   Primeiro copia tudo que não foi para a quarentena, do jeito que está.
   Depois aplica uma regra de cada vez. Cada regra só mexe em linhas que
   ainda estão 'OK', então a ordem das regras é a ordem de prioridade.
   ===================================================================== */
INSERT INTO stg_medicao_limpa (id_medicao, id_usina, cod_usina, cod_fonte, potencia_mw, data_hora,
                               energia_mwh, energia_original_mwh, disponibilidade_mw,
                               origem, recebido_em)
SELECT m.id_medicao, m.id_usina, u.cod_usina, f.cod_fonte, u.potencia_mw, m.data_hora,
       m.energia_mwh, m.energia_mwh, m.disponibilidade_mw,
       m.origem, m.recebido_em
FROM campo_real_energia.medicao_geracao m
LEFT JOIN campo_real_energia.usina u         ON u.id_usina = m.id_usina
LEFT JOIN campo_real_energia.fonte_energia f ON f.id_fonte = u.id_fonte
WHERE m.id_medicao NOT IN (SELECT id_medicao FROM quarentena_medicao);

-- 7.1 Usina nula ou que não existe no cadastro: SINALIZAR.
--     No fato essas linhas apontam para a "Usina desconhecida" (-1).
UPDATE stg_medicao_limpa
   SET flag_qualidade = 'USINA_DESCONHECIDA'
 WHERE cod_usina IS NULL;

-- 7.2 Energia sem valor: SINALIZAR. Fica NULL (não inventamos a leitura).
UPDATE stg_medicao_limpa
   SET flag_qualidade = 'SEM_LEITURA'
 WHERE flag_qualidade = 'OK' AND energia_mwh IS NULL;

-- 7.3 Energia negativa: CORRIGIR para 0.
--     Negativo é o consumo dos serviços auxiliares; a geração foi zero.
UPDATE stg_medicao_limpa
   SET energia_mwh = 0, flag_qualidade = 'NEGATIVO_ZERADO'
 WHERE flag_qualidade = 'OK' AND energia_mwh < 0;

-- 7.4 Lançamento MANUAL em kWh: CORRIGIR dividindo por 1000.
--     Dá para ter certeza: o valor é maior que a potência e, dividido
--     por 1000, volta a caber na usina.
UPDATE stg_medicao_limpa
   SET energia_mwh = ROUND(energia_mwh / 1000, 3), flag_qualidade = 'KWH_CONVERTIDO'
 WHERE flag_qualidade = 'OK' AND origem = 'MANUAL'
   AND energia_mwh > potencia_mw AND energia_mwh / 1000 <= potencia_mw;

-- 7.5 Outras leituras maiores que a potência instalada: SINALIZAR e pôr NULL.
--     Em 1 hora a usina não gera mais MWh do que a potência em MW, então o
--     valor é impossível, mas não sabemos qual era o certo.
UPDATE stg_medicao_limpa
   SET energia_mwh = NULL, flag_qualidade = 'ACIMA_DA_POTENCIA'
 WHERE flag_qualidade = 'OK' AND energia_mwh > potencia_mw;

-- 7.6 Geração com disponibilidade zero: CORRIGIR para 0.
--     A própria linha diz que a usina estava indisponível (parada).
UPDATE stg_medicao_limpa
   SET energia_mwh = 0, flag_qualidade = 'GERACAO_EM_PARADA'
 WHERE flag_qualidade = 'OK' AND disponibilidade_mw = 0 AND energia_mwh > 0;

-- 7.7 Usina solar gerando de noite: CORRIGIR para 0 (sem sol não gera).
UPDATE stg_medicao_limpa
   SET energia_mwh = 0, flag_qualidade = 'SOLAR_A_NOITE'
 WHERE flag_qualidade = 'OK' AND cod_fonte = 'UFV'
   AND HOUR(data_hora) NOT BETWEEN 6 AND 18 AND energia_mwh > 0;

-- 7.8 Medidor travado: SINALIZAR (o valor é plausível, então é mantido).
--     Critério: as 24 leituras do dia iguais e diferentes de zero.
UPDATE stg_medicao_limpa m
JOIN (
    SELECT cod_usina, DATE(data_hora) AS dia
    FROM stg_medicao_limpa
    WHERE cod_usina IS NOT NULL
    GROUP BY cod_usina, DATE(data_hora)
    HAVING COUNT(*) = 24 AND COUNT(DISTINCT energia_mwh) = 1 AND MIN(energia_mwh) > 0
) AS travado
  ON travado.cod_usina = m.cod_usina AND travado.dia = DATE(m.data_hora)
SET m.flag_qualidade = 'MEDIDOR_TRAVADO'
WHERE m.flag_qualidade = 'OK';

-- 7.9 Atualidade (não muda a energia, só marca)
UPDATE stg_medicao_limpa
   SET flag_atualidade = 'ATRASADO'
 WHERE recebido_em > data_hora + INTERVAL 24 HOUR;

UPDATE stg_medicao_limpa
   SET flag_atualidade = 'RELOGIO_ERRADO'
 WHERE recebido_em < data_hora;


/* =====================================================================
   PASSO 8 - fato_pld (grão: 1 submercado x 1 hora)
   ===================================================================== */
INSERT INTO fato_pld (sk_tempo, sk_submercado, pld_rs_mwh, flag_qualidade)
SELECT t.sk_tempo, s.sk_submercado, p.pld_rs_mwh, p.flag_qualidade
FROM stg_pld_limpo p
JOIN dim_tempo t      ON t.data_hora = p.data_hora
JOIN dim_submercado s ON s.cod_submercado = p.cod_submercado;


/* =====================================================================
   PASSO 9 - fato_geracao (grão: 1 usina x 1 hora)
   ---------------------------------------------------------------------
   - usina sem cadastro  -> sk_usina = -1 e sk_submercado = -1
   - hora sem parada     -> sk_parada = 0
   - o PLD é o da mesma hora no submercado da usina
   - receita = energia x PLD
   ===================================================================== */
INSERT INTO fato_geracao (id_medicao, sk_tempo, sk_usina, sk_submercado, sk_parada,
                          energia_mwh, disponibilidade_mw, capacidade_mwh,
                          pld_rs_mwh, receita_rs, flag_qualidade, flag_atualidade)
SELECT m.id_medicao,
       t.sk_tempo,
       COALESCE(du.sk_usina, -1),
       COALESCE(ds.sk_submercado, -1),
       COALESCE(dp.sk_parada, 0),
       m.energia_mwh,
       m.disponibilidade_mw,
       du.potencia_mw,
       p.pld_rs_mwh,
       ROUND(m.energia_mwh * p.pld_rs_mwh, 2),
       m.flag_qualidade,
       m.flag_atualidade
FROM stg_medicao_limpa m
JOIN dim_tempo t            ON t.data_hora = m.data_hora
LEFT JOIN dim_usina du      ON du.cod_usina = m.cod_usina
                           AND DATE(m.data_hora) BETWEEN du.vigencia_inicio AND du.vigencia_fim
LEFT JOIN dim_submercado ds ON ds.cod_submercado = du.cod_submercado
LEFT JOIN stg_pld_limpo p   ON p.cod_submercado = du.cod_submercado
                           AND p.data_hora      = m.data_hora
LEFT JOIN dim_parada dp     ON dp.cod_usina = m.cod_usina
                           AND m.data_hora BETWEEN dp.inicio AND dp.fim;


/* =====================================================================
   PASSO 10 - Estimativa do que deixou de ser gerado nas paradas
   ---------------------------------------------------------------------
   Para cada hora parada usamos a média que a MESMA usina gerou no MESMO
   mês e na MESMA hora do dia, nos dias sem parada.
   Se o mês inteiro foi de parada (biomassa em dezembro, na entressafra),
   não há base de comparação e a estimativa fica 0.
   ===================================================================== */
UPDATE fato_geracao f
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
JOIN (
    SELECT g.sk_usina, t2.mes, t2.hora, AVG(g.energia_mwh) AS media_mwh
    FROM fato_geracao g
    JOIN dim_tempo t2 ON t2.sk_tempo = g.sk_tempo
    WHERE g.sk_parada = 0
    GROUP BY g.sk_usina, t2.mes, t2.hora
) AS ref
  ON ref.sk_usina = f.sk_usina AND ref.mes = t.mes AND ref.hora = t.hora
SET f.energia_perdida_mwh = ROUND(ref.media_mwh, 3),
    f.receita_perdida_rs  = ROUND(ref.media_mwh * f.pld_rs_mwh, 2)
WHERE f.sk_parada <> 0;


/* =====================================================================
   PASSO 11 - fato_clima (grão: 1 usina x 1 hora)
   ---------------------------------------------------------------------
   O ponto de clima é a coordenada da própria usina, então a ligação é
   direta pelo código da usina.
   ===================================================================== */
INSERT INTO fato_clima (sk_tempo, sk_usina, temperatura_c, radiacao_wm2, vento_kmh, chuva_mm)
SELECT t.sk_tempo, du.sk_usina, c.temperatura_c, c.radiacao_wm2, c.vento_kmh, c.chuva_mm
FROM campo_real_energia.clima_horario c
JOIN dim_tempo t  ON t.data_hora = c.data_hora
JOIN dim_usina du ON du.cod_usina = c.cod_usina AND du.registro_atual = 1;


/* =====================================================================
   PASSO 12 - Conferência
   ===================================================================== */
SELECT 'dim_tempo'        AS tabela, COUNT(*) AS linhas FROM dim_tempo
UNION ALL SELECT 'dim_submercado',     COUNT(*) FROM dim_submercado
UNION ALL SELECT 'dim_usina',          COUNT(*) FROM dim_usina
UNION ALL SELECT 'dim_parada',         COUNT(*) FROM dim_parada
UNION ALL SELECT 'stg_pld_limpo',      COUNT(*) FROM stg_pld_limpo
UNION ALL SELECT 'stg_medicao_limpa',  COUNT(*) FROM stg_medicao_limpa
UNION ALL SELECT 'quarentena_medicao', COUNT(*) FROM quarentena_medicao
UNION ALL SELECT 'fato_geracao',       COUNT(*) FROM fato_geracao
UNION ALL SELECT 'fato_pld',           COUNT(*) FROM fato_pld
UNION ALL SELECT 'fato_clima',         COUNT(*) FROM fato_clima;

SELECT flag_qualidade, COUNT(*) AS linhas FROM fato_geracao GROUP BY flag_qualidade ORDER BY linhas DESC;
SELECT flag_atualidade, COUNT(*) AS linhas FROM fato_geracao GROUP BY flag_atualidade ORDER BY linhas DESC;
SELECT motivo, COUNT(*) AS linhas FROM quarentena_medicao GROUP BY motivo;
SELECT flag_qualidade, COUNT(*) AS linhas FROM fato_pld GROUP BY flag_qualidade;
