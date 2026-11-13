/* =====================================================================
   06 - INDICADORES (consultas que respondem às perguntas de negócio)
   ---------------------------------------------------------------------
   Todas as consultas leem SOMENTE do data warehouse (dw_campo_real).
   Servem para conferir os números do painel do Power BI.
   Ano de análise: 2025 (o fato de geração só tem 2025).
   ===================================================================== */

USE dw_campo_real;


/* ---------------------------------------------------------------------
   PERGUNTA 1 - Quanto geramos por usina, fonte e submercado?
   Fator de capacidade = energia gerada / (potência x horas)
   --------------------------------------------------------------------- */

-- 1a. Por usina
SELECT u.nome                                                  AS usina,
       u.fonte,
       u.cod_submercado                                        AS submercado,
       ROUND(SUM(f.energia_mwh))                               AS geracao_mwh,
       ROUND(100 * SUM(f.energia_mwh) / SUM(f.capacidade_mwh), 1) AS fator_capacidade_pct
FROM fato_geracao f
JOIN dim_usina u ON u.sk_usina = f.sk_usina
WHERE f.sk_usina <> -1
GROUP BY u.nome, u.fonte, u.cod_submercado
ORDER BY geracao_mwh DESC;

-- 1b. Por fonte
SELECT u.fonte,
       ROUND(SUM(f.energia_mwh))                               AS geracao_mwh,
       ROUND(100 * SUM(f.energia_mwh) / SUM(f.capacidade_mwh), 1) AS fator_capacidade_pct
FROM fato_geracao f
JOIN dim_usina u ON u.sk_usina = f.sk_usina
WHERE f.sk_usina <> -1
GROUP BY u.fonte
ORDER BY geracao_mwh DESC;

-- 1c. Por submercado
SELECT s.nome                    AS submercado,
       ROUND(SUM(f.energia_mwh)) AS geracao_mwh
FROM fato_geracao f
JOIN dim_submercado s ON s.sk_submercado = f.sk_submercado
GROUP BY s.nome
ORDER BY geracao_mwh DESC;

-- 1d. Evolução mensal
SELECT t.mes, t.nome_mes,
       ROUND(SUM(f.energia_mwh)) AS geracao_mwh
FROM fato_geracao f
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
GROUP BY t.mes, t.nome_mes
ORDER BY t.mes;


/* ---------------------------------------------------------------------
   PERGUNTA 2 - Quanto a geração vale a preço de mercado?
   Receita valorada ao PLD = soma de (geração da hora x PLD da hora)
   --------------------------------------------------------------------- */
SELECT ROUND(SUM(energia_mwh))                       AS geracao_mwh,
       ROUND(SUM(receita_rs), 2)                     AS receita_rs,
       ROUND(SUM(receita_rs) / SUM(energia_mwh), 2)  AS preco_capturado_rs_mwh
FROM fato_geracao
WHERE sk_usina <> -1;

SELECT u.nome                    AS usina,
       ROUND(SUM(f.receita_rs))  AS receita_rs
FROM fato_geracao f
JOIN dim_usina u ON u.sk_usina = f.sk_usina
WHERE f.sk_usina <> -1
GROUP BY u.nome
ORDER BY receita_rs DESC;


/* ---------------------------------------------------------------------
   PERGUNTA 3 - Qual fonte captura o melhor preço?
   Preço capturado  = receita / geração
   Razão de captura = preço capturado / PLD médio (dos submercados em que
                      a fonte tem usina, em 2025)
   --------------------------------------------------------------------- */
SELECT g.fonte,
       ROUND(g.receita_rs / g.geracao_mwh, 2)                    AS preco_capturado_rs_mwh,
       ROUND(p.pld_medio, 2)                                     AS pld_medio_rs_mwh,
       ROUND((g.receita_rs / g.geracao_mwh) / p.pld_medio, 2)    AS razao_captura
FROM (
    SELECT u.fonte, SUM(f.receita_rs) AS receita_rs, SUM(f.energia_mwh) AS geracao_mwh
    FROM fato_geracao f
    JOIN dim_usina u ON u.sk_usina = f.sk_usina
    WHERE f.sk_usina <> -1 AND f.receita_rs IS NOT NULL
    GROUP BY u.fonte
) AS g
JOIN (
    SELECT fs.fonte, AVG(fp.pld_rs_mwh) AS pld_medio
    FROM (SELECT DISTINCT fonte, cod_submercado FROM dim_usina WHERE sk_usina <> -1) AS fs
    JOIN dim_submercado s ON s.cod_submercado = fs.cod_submercado
    JOIN fato_pld fp      ON fp.sk_submercado = s.sk_submercado
    JOIN dim_tempo t      ON t.sk_tempo = fp.sk_tempo
    WHERE t.ano = 2025
    GROUP BY fs.fonte
) AS p ON p.fonte = g.fonte
ORDER BY razao_captura DESC;


/* ---------------------------------------------------------------------
   PERGUNTA 4 - Em que horas e meses o PLD é mais alto? Geramos nessas horas?
   --------------------------------------------------------------------- */

-- 4a. Mapa de calor: PLD médio por hora (linhas) e mês (colunas), 2025
SELECT t.hora,
       ROUND(AVG(CASE WHEN t.mes = 1  THEN p.pld_rs_mwh END)) AS jan,
       ROUND(AVG(CASE WHEN t.mes = 2  THEN p.pld_rs_mwh END)) AS fev,
       ROUND(AVG(CASE WHEN t.mes = 3  THEN p.pld_rs_mwh END)) AS mar,
       ROUND(AVG(CASE WHEN t.mes = 4  THEN p.pld_rs_mwh END)) AS abr,
       ROUND(AVG(CASE WHEN t.mes = 5  THEN p.pld_rs_mwh END)) AS mai,
       ROUND(AVG(CASE WHEN t.mes = 6  THEN p.pld_rs_mwh END)) AS jun,
       ROUND(AVG(CASE WHEN t.mes = 7  THEN p.pld_rs_mwh END)) AS jul,
       ROUND(AVG(CASE WHEN t.mes = 8  THEN p.pld_rs_mwh END)) AS ago,
       ROUND(AVG(CASE WHEN t.mes = 9  THEN p.pld_rs_mwh END)) AS `set`,
       ROUND(AVG(CASE WHEN t.mes = 10 THEN p.pld_rs_mwh END)) AS `out`,
       ROUND(AVG(CASE WHEN t.mes = 11 THEN p.pld_rs_mwh END)) AS nov,
       ROUND(AVG(CASE WHEN t.mes = 12 THEN p.pld_rs_mwh END)) AS dez
FROM fato_pld p
JOIN dim_tempo t ON t.sk_tempo = p.sk_tempo
WHERE t.ano = 2025
GROUP BY t.hora
ORDER BY t.hora;

-- 4b. Perfil horário: PLD médio e geração média de cada fonte (MWh por hora)
SELECT t.hora,
       ROUND(AVG(f.pld_rs_mwh))                                              AS pld_medio,
       ROUND(SUM(CASE WHEN u.cod_fonte = 'UHE' THEN f.energia_mwh END) / 365) AS hidreletrica,
       ROUND(SUM(CASE WHEN u.cod_fonte = 'PCH' THEN f.energia_mwh END) / 365) AS pch,
       ROUND(SUM(CASE WHEN u.cod_fonte = 'EOL' THEN f.energia_mwh END) / 365) AS eolica,
       ROUND(SUM(CASE WHEN u.cod_fonte = 'UFV' THEN f.energia_mwh END) / 365) AS solar,
       ROUND(SUM(CASE WHEN u.cod_fonte = 'BIO' THEN f.energia_mwh END) / 365) AS biomassa,
       ROUND(SUM(CASE WHEN u.cod_fonte = 'UTE' THEN f.energia_mwh END) / 365) AS termica
FROM fato_geracao f
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
JOIN dim_usina u ON u.sk_usina = f.sk_usina
WHERE f.sk_usina <> -1
GROUP BY t.hora
ORDER BY t.hora;

-- 4c. Geração e preço por patamar de carga
SELECT t.patamar_carga,
       ROUND(SUM(f.energia_mwh))                         AS geracao_mwh,
       ROUND(100 * SUM(f.energia_mwh) / (SELECT SUM(energia_mwh) FROM fato_geracao WHERE sk_usina <> -1), 1) AS pct_da_geracao,
       ROUND(SUM(f.receita_rs) / SUM(f.energia_mwh), 2)  AS preco_capturado_rs_mwh
FROM fato_geracao f
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
WHERE f.sk_usina <> -1
GROUP BY t.patamar_carga;


/* ---------------------------------------------------------------------
   PERGUNTA 5 - Quanto perdemos com paradas?
   --------------------------------------------------------------------- */

-- 5a. Por tipo de parada
SELECT p.tipo_parada,
       COUNT(*)                            AS horas_indisponiveis,
       ROUND(SUM(f.energia_perdida_mwh))   AS energia_nao_gerada_mwh,
       ROUND(SUM(f.receita_perdida_rs))    AS receita_nao_gerada_rs
FROM fato_geracao f
JOIN dim_parada p ON p.sk_parada = f.sk_parada
WHERE f.sk_parada <> 0
GROUP BY p.tipo_parada;

-- 5b. Por parada
SELECT u.nome AS usina, p.tipo_parada, p.motivo,
       COUNT(*)                            AS horas_indisponiveis,
       ROUND(SUM(f.energia_perdida_mwh))   AS energia_nao_gerada_mwh,
       ROUND(SUM(f.receita_perdida_rs))    AS receita_nao_gerada_rs
FROM fato_geracao f
JOIN dim_parada p ON p.sk_parada = f.sk_parada
JOIN dim_usina u  ON u.sk_usina = f.sk_usina
WHERE f.sk_parada <> 0
GROUP BY u.nome, p.tipo_parada, p.motivo
ORDER BY receita_nao_gerada_rs DESC;


/* ---------------------------------------------------------------------
   PERGUNTA 6 - O clima explica a nossa geração?
   Correlação de Pearson (de -1 a 1) entre a geração da hora e o clima:
     solar  x radiação solar
     eólica x velocidade do vento
   Só entram horas sem parada e com leitura.
   --------------------------------------------------------------------- */
SELECT u.nome AS usina,
       u.fonte,
       CASE WHEN u.cod_fonte = 'UFV' THEN 'radiação solar' ELSE 'vento a 100 m' END AS variavel_clima,
       ROUND(
         (AVG(f.energia_mwh * x.clima) - AVG(f.energia_mwh) * AVG(x.clima))
         / (STDDEV_POP(f.energia_mwh) * STDDEV_POP(x.clima)), 2)                    AS correlacao
FROM fato_geracao f
JOIN dim_usina u ON u.sk_usina = f.sk_usina
JOIN (
    SELECT c.sk_tempo, c.sk_usina,
           CASE WHEN du.cod_fonte = 'UFV' THEN c.radiacao_wm2 ELSE c.vento_kmh END AS clima
    FROM fato_clima c
    JOIN dim_usina du ON du.sk_usina = c.sk_usina
) AS x ON x.sk_tempo = f.sk_tempo AND x.sk_usina = f.sk_usina
WHERE u.cod_fonte IN ('UFV', 'EOL')
  AND f.sk_parada = 0
  AND f.energia_mwh IS NOT NULL
GROUP BY u.nome, u.fonte, u.cod_fonte;


/* ---------------------------------------------------------------------
   PERGUNTA 7 - Podemos confiar nesses números?
   --------------------------------------------------------------------- */

-- 7a. Índice de qualidade por dimensão (100% = nenhuma falha)
SELECT dimensao,
       COUNT(*)                        AS regras,
       SUM(registros_falha)            AS registros_com_falha,
       ROUND(100 - 100 * SUM(registros_falha) / SUM(registros_avaliados), 3) AS indice_qualidade_pct
FROM dq_metricas
GROUP BY dimensao
ORDER BY indice_qualidade_pct;

-- 7b. Índice de qualidade por tabela
SELECT tabela,
       COUNT(*)                        AS regras,
       SUM(registros_falha)            AS registros_com_falha,
       ROUND(100 - 100 * SUM(registros_falha) / SUM(registros_avaliados), 3) AS indice_qualidade_pct
FROM dq_metricas
GROUP BY tabela
ORDER BY indice_qualidade_pct;

-- 7c. Antes x depois da limpeza (total da empresa)
SELECT indicador, valor_antes, valor_depois, diferenca, diferenca_pct
FROM dq_antes_depois
WHERE recorte = 'Total';

-- 7d. Quantas linhas do fato têm alguma marca de qualidade
SELECT flag_qualidade, COUNT(*) AS linhas
FROM fato_geracao
GROUP BY flag_qualidade
ORDER BY linhas DESC;
