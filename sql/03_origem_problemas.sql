/* =====================================================================
   03 - BANCO DE ORIGEM (parte 2: passos 5 e 6 do script da professora)
   ---------------------------------------------------------------------
   Cópia sem alteração dos passos 5 e 6 do campo_real_energia.sql.
   Rodar DEPOIS de carregar o PLD (python/01_extrair_pld.py), porque o
   passo 5.4 mexe na tabela pld_horario.
   ===================================================================== */

USE campo_real_energia;

/* =====================================================================
   PASSO 5 - Simular a vida real: falhas de sistema, digitação e integração
   ---------------------------------------------------------------------
   Nenhum dado real é limpo. Este passo reproduz o que acontece numa
   comercializadora de verdade: medidor que trava, reprocessamento que
   duplica, operador que digita errado, cadastro feito às pressas,
   integração que atrasa.

   IMPORTANTE: rode este passo DEPOIS de carregar o PLD (passo 4.7 ou 4.9).

   Missão dos alunos: encontrar os problemas, classificá-los nas
   dimensões de qualidade (completude, unicidade, validade, consistência,
   acurácia, atualidade/tempestividade, integridade referencial),
   medir quantos registros cada um afeta e propor o tratamento.
   ===================================================================== */

SET @uhe1 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-UHE-001');
SET @pch2 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-PCH-002');
SET @eol3 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-EOL-003');
SET @ufv4 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-UFV-004');
SET @bio5 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-BIO-005');
SET @ufv6 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-UFV-006');
SET @eol7 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-EOL-007');
SET @uhe8 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-UHE-008');
SET @ute9 := (SELECT id_usina FROM usina WHERE cod_usina = 'CRE-UTE-009');

-- 5.1 Cadastro de usinas feito às pressas
INSERT INTO usina (cod_usina, nome, id_fonte, cod_submercado, uf, municipio,
                   latitude, longitude, potencia_mw, data_inicio_operacao)
SELECT 'CRE-EOL-07', 'Eol Ventos do Potiguar ', id_fonte, cod_submercado, uf, '',
       latitude, longitude, potencia_mw, data_inicio_operacao
FROM usina WHERE cod_usina = 'CRE-EOL-007';

UPDATE usina SET latitude = 15.803000              WHERE cod_usina = 'CRE-UFV-004';
UPDATE usina SET data_inicio_operacao = '2031-02-01' WHERE cod_usina = 'CRE-UFV-006';
UPDATE usina SET uf = 'PE'                          WHERE cod_usina = 'CRE-BIO-005';

-- 5.2 Registro de parada lançado manualmente
INSERT INTO parada_usina (id_usina, inicio, fim, tipo, motivo)
VALUES (@ufv4, '2025-11-05 18:00:00', '2025-11-05 08:00:00', 'Forçada', 'Limpeza emergencial dos módulos');

-- 5.3 Falhas no sistema de medição
-- falha de comunicação
UPDATE medicao_geracao SET energia_mwh = NULL
 WHERE id_usina = @uhe8 AND data_hora BETWEEN '2025-03-05 10:00:00' AND '2025-03-05 15:00:00';

-- dia que não chegou
DELETE FROM medicao_geracao
 WHERE id_usina = @eol3 AND DATE(data_hora) = '2025-11-10';

-- dados que pararam de chegar no fim do ano
DELETE FROM medicao_geracao
 WHERE id_usina = @ufv4 AND data_hora >= '2025-12-29 00:00:00';

-- reprocessamento da integração
INSERT INTO medicao_geracao (id_usina, data_hora, energia_mwh, disponibilidade_mw, origem, recebido_em)
SELECT id_usina, data_hora, energia_mwh, disponibilidade_mw, origem, recebido_em + INTERVAL 1 DAY
FROM medicao_geracao
WHERE id_usina = @ufv4 AND DATE(data_hora) = '2025-01-20';

-- lançamento manual por cima da leitura automática
INSERT INTO medicao_geracao (id_usina, data_hora, energia_mwh, disponibilidade_mw, origem, recebido_em)
SELECT id_usina, data_hora, ROUND(energia_mwh * 1.10, 3), disponibilidade_mw, 'MANUAL', recebido_em + INTERVAL 2 DAY
FROM medicao_geracao
WHERE id_usina = @pch2 AND data_hora BETWEEN '2025-06-01 08:00:00' AND '2025-06-01 11:00:00';

-- consumo dos serviços auxiliares registrado como geração
UPDATE medicao_geracao SET energia_mwh = -0.850
 WHERE id_usina = @eol7 AND data_hora BETWEEN '2025-02-03 01:00:00' AND '2025-02-03 04:00:00';

-- erro de digitação no ano e registro sem usina
INSERT INTO medicao_geracao (id_usina, data_hora, energia_mwh, disponibilidade_mw, origem, recebido_em) VALUES
  (@ufv6, '2052-05-14 10:00:00', 55.200, 90.00, 'MANUAL', '2025-05-14 11:10:00'),
  (NULL,  '2025-10-20 14:00:00', 33.100, NULL,  'MANUAL', '2025-10-20 15:20:00');

-- medições de um equipamento que não está no cadastro
INSERT INTO medicao_geracao (id_usina, data_hora, energia_mwh, disponibilidade_mw, origem, recebido_em)
SELECT 99, data_hora, energia_mwh, disponibilidade_mw, origem, recebido_em
FROM medicao_geracao
WHERE id_usina = @eol7 AND DATE(data_hora) = '2025-10-15';

-- vírgula deslocada e pico de leitura
UPDATE medicao_geracao SET energia_mwh = energia_mwh * 10
 WHERE id_usina = @uhe1 AND data_hora = '2025-04-22 14:00:00';
UPDATE medicao_geracao SET energia_mwh = 499.000
 WHERE id_usina = @eol3 AND data_hora = '2025-07-03 03:00:00';

-- medidor travado
UPDATE medicao_geracao SET energia_mwh = 31.250
 WHERE id_usina = @bio5 AND data_hora BETWEEN '2025-09-01 00:00:00' AND '2025-09-03 23:00:00';

-- leitura com relógio do medidor errado
UPDATE medicao_geracao SET energia_mwh = 15.400
 WHERE id_usina = @ufv6 AND data_hora BETWEEN '2025-08-12 20:00:00' AND '2025-08-12 23:00:00';

-- geração lançada durante manutenção
UPDATE medicao_geracao SET energia_mwh = 132.000
 WHERE id_usina = @ute9 AND data_hora BETWEEN '2025-06-05 18:00:00' AND '2025-06-05 21:00:00';

-- planilha digitada em kWh
UPDATE medicao_geracao SET energia_mwh = energia_mwh * 1000, origem = 'MANUAL'
 WHERE id_usina = @bio5 AND DATE(data_hora) = '2025-05-10';

-- integração atrasada
UPDATE medicao_geracao SET recebido_em = '2026-02-10 09:00:00' + INTERVAL HOUR(data_hora) MINUTE
 WHERE id_usina = @uhe8 AND data_hora >= '2025-12-20 00:00:00';

-- relógio do servidor errado
UPDATE medicao_geracao SET recebido_em = data_hora - INTERVAL 3 DAY
 WHERE id_usina = @pch2 AND DATE(data_hora) = '2025-08-05';

-- 5.4 Problemas na base de preços
DELETE FROM pld_horario
 WHERE cod_submercado = 'NE' AND DATE(data_hora) = '2025-05-18';
UPDATE pld_horario SET pld_rs_mwh = 15422.30
 WHERE cod_submercado = 'SE' AND data_hora = '2025-02-10 19:00:00';
UPDATE pld_horario SET pld_rs_mwh = -58.60
 WHERE cod_submercado = 'S'  AND data_hora = '2025-03-12 03:00:00';


/* =====================================================================
   PASSO 6 - Verificação final do banco
   ===================================================================== */
SELECT 'submercado'       AS tabela, COUNT(*) AS linhas FROM submercado
UNION ALL SELECT 'fonte_energia',    COUNT(*) FROM fonte_energia
UNION ALL SELECT 'usina',            COUNT(*) FROM usina               -- 10
UNION ALL SELECT 'feriado_nacional', COUNT(*) FROM feriado_nacional
UNION ALL SELECT 'parada_usina',     COUNT(*) FROM parada_usina
UNION ALL SELECT 'medicao_geracao',  COUNT(*) FROM medicao_geracao     -- 78.798
UNION ALL SELECT 'stg_pld_horario',  COUNT(*) FROM stg_pld_horario
UNION ALL SELECT 'pld_horario',      COUNT(*) FROM pld_horario         -- 35.016
UNION ALL SELECT 'log_carga',        COUNT(*) FROM log_carga;

-- Teste rápido: as duas tabelas "conversam" pela hora e pelo submercado?
SELECT u.nome, m.data_hora, m.energia_mwh, p.pld_rs_mwh
FROM medicao_geracao m
JOIN usina u       ON u.id_usina = m.id_usina
JOIN pld_horario p ON p.cod_submercado = u.cod_submercado
                  AND p.data_hora      = m.data_hora
WHERE m.data_hora = '2025-09-15 12:00:00';
