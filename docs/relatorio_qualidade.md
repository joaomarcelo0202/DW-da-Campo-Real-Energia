# Relatório de qualidade de dados

- Medição: `python/03_qualidade.py` (não altera nada, só mede).
- Limpeza: `sql/05_dw_carga.sql` (as tabelas de origem não são alteradas).
- Evidências no banco: `dw_campo_real.dq_profiling`, `dq_metricas` e
  `dq_antes_depois`.

Foram executadas **30 regras** nas 7 dimensões de qualidade; **24 encontraram
falha**. Tipos de decisão usados:

- **Corrigir**: só quando dá para ter certeza do valor certo.
- **Sinalizar**: o dado entra no DW com uma marca (`flag_qualidade` ou
  `flag_atualidade`) e, se o valor não é confiável, fica NULL.
- **Quarentena**: a linha não entra no DW e fica guardada em
  `quarentena_medicao` com o motivo.
- **Descartar**: a linha não entra no DW.

## 1. Problemas encontrados

### Medições (`medicao_geracao`, 78.798 linhas)

| Dimensão | Problema | Linhas | Decisão | Por quê |
|----------|----------|-------:|---------|---------|
| Completude | Energia nula (UHE Tocantins, 05/03, 10h-15h) | 6 | Sinalizar (`SEM_LEITURA`) | Falha de comunicação. Não inventamos a leitura: fica NULL. |
| Completude | Medição sem usina | 1 | Sinalizar (`USINA_DESCONHECIDA`) | Vai para o membro desconhecido (-1). |
| Completude | Horas sem medição (EOL Coxilha em 10/11; UFV Minas de 29 a 31/12) | 96 | Sinalizar | As horas ficam sem linha no fato. Preencher seria inventar dado. |
| Unicidade | Mesma usina e hora duas vezes (UFV Minas em 20/01: 24; PCH em 01/06: 4) | 28 | Quarentena (`DUPLICADA`) | Fica a leitura automática (SCADA); se as duas são SCADA, a que chegou primeiro. |
| Validade | Energia negativa (EOL Potiguar, 03/02) | 4 | Corrigir para 0 | Negativo é consumo dos serviços auxiliares; a geração foi zero. |
| Validade | Data no ano 2052 | 1 | Quarentena | Ano digitado errado, e a hora certa já tem leitura. |
| Consistência | Solar gerando de noite (UFV Sertão, 12/08, 20h-23h) | 4 | Corrigir para 0 | Sem sol não há geração; o relógio do medidor estava errado. |
| Consistência | Geração com disponibilidade zero (UTE Gás Norte, 05/06) | 4 | Corrigir para 0 | A usina estava em parada programada (overhaul da turbina). |
| Consistência | Recebido antes da hora medida (PCH, 05/08) | 24 | Sinalizar (`RELOGIO_ERRADO`) | A energia está certa, só o relógio do servidor estava errado. |
| Acurácia | Energia maior que a potência: planilha em kWh (Biomassa, 10/05) | 24 | Corrigir (dividir por 1000) | Lançamento manual; dividido por 1000 volta a caber na potência da usina. |
| Acurácia | Energia maior que a potência: vírgula deslocada (UHE Iguaçu) e pico (EOL Coxilha) | 2 | Sinalizar (`ACIMA_DA_POTENCIA`), fica NULL | Valor impossível, mas não temos certeza do valor certo. |
| Acurácia | Medidor travado em 31,250 (Biomassa, 01 a 03/09) | 72 | Sinalizar (`MEDIDOR_TRAVADO`) | O valor é plausível, então é mantido com a marca. |
| Integridade | Usina 99 não existe no cadastro | 24 | Sinalizar (`USINA_DESCONHECIDA`) | Vai para o membro desconhecido (-1), sem PLD e sem receita. |
| Atualidade | Chegou mais de 24 h depois (UHE Tocantins desde 20/12 + duplicadas) | 316 | Sinalizar (`ATRASADO`) | A energia é mantida. 288 ficam no fato; as outras 28 são as duplicadas da quarentena. |
| Atualidade | Usina parou de enviar (UFV Minas desde 29/12) | 1 usina | Sinalizar | Avisar a operação. |

### Cadastro de usinas (`usina`, 10 linhas)

| Dimensão | Problema | Linhas | Decisão | Por quê |
|----------|----------|-------:|---------|---------|
| Unicidade / Validade / Completude | EOL Ventos do Potiguar cadastrada duas vezes (código `CRE-EOL-07`, município vazio) | 1 | Descartar | Código fora do padrão e nenhuma medição usa esse cadastro. |
| Validade | Latitude +15,80 na UFV Campo Real Minas (fora do Brasil) | 1 | Corrigir o sinal | Janaúba/MG fica em -15,80. |
| Validade | Início de operação em 2031 (UFV Sertão do Sol) | 1 | Sinalizar (NULL) | A usina já gera em 2025, mas não sabemos a data certa. |
| Consistência | UF "PE" em usina do submercado Sudeste (Biomassa) | 1 | Corrigir para SP | O município (Sertãozinho) e as coordenadas ficam em São Paulo. |

### Paradas (`parada_usina`, 11 linhas)

| Dimensão | Problema | Linhas | Decisão | Por quê |
|----------|----------|-------:|---------|---------|
| Validade | Fim antes do início (UFV Minas, 05/11) | 1 | Descartar | Não dá para saber o horário certo. |

### PLD (`pld_horario`, 65.448 linhas)

| Dimensão | Problema | Linhas | Decisão | Por quê |
|----------|----------|-------:|---------|---------|
| Completude | Nordeste sem o dia 18/05/2025 | 24 | Corrigir | As horas existem na camada raw. |
| Validade | R$ 15.422,30 (acima do teto de R$ 1.542,23) | 1 | Corrigir | O raw tem o valor original da CCEE. |
| Validade | R$ -58,60 (abaixo do piso de R$ 58,60) | 1 | Corrigir | O raw tem o valor original da CCEE. |

Os três problemas do PLD foram resolvidos do mesmo jeito: o PLD limpo é
montado a partir da **camada raw**, que guarda o dado como veio da CCEE.
É para isso que o raw existe.

### Clima (`clima_horario`, 78.840 linhas)

Nenhuma falha: sem nulos, sem horas faltando e valores dentro do possível.

## 2. Índice de qualidade

Índice = 100% - (registros com falha / registros avaliados).

| Dimensão | Regras | Registros com falha | Índice |
|----------|-------:|--------------------:|-------:|
| Atualidade | 2 | 317 | 99,598% |
| Acurácia | 3 | 98 | 99,959% |
| Completude | 7 | 128 | 99,972% |
| Unicidade | 3 | 29 | 99,980% |
| Consistência | 5 | 35 | 99,985% |
| Integridade referencial | 3 | 24 | 99,985% |
| Validade | 7 | 11 | 99,995% |

| Tabela | Regras | Registros com falha | Índice |
|--------|-------:|--------------------:|-------:|
| usina | 6 | 6 | 90,000% |
| parada_usina | 2 | 1 | 95,455% |
| medicao_geracao | 14 | 607 | 99,937% |
| pld_horario | 3 | 28 | 99,986% |
| stg_pld_horario | 1 | 0 | 100% |
| clima_horario | 4 | 0 | 100% |

O índice parece ótimo (quase tudo acima de 99,9%), mas a próxima seção
mostra que poucas linhas erradas mudam muito o resultado.

## 3. Antes x depois da limpeza

"Antes" é a conta feita direto nas tabelas de origem; "depois" é a conta no
DW. Ano de 2025, só usinas cadastradas.

| Indicador | Antes | Depois | Diferença |
|-----------|------:|-------:|----------:|
| Geração (MWh) | 3.883.505 | 3.118.741 | -19,7% |
| Receita valorada ao PLD (R$) | 808.075.408 | 637.819.882 | -21,1% |
| Preço capturado (R$/MWh) | 208,08 | 204,51 | -1,7% |
| Fator de capacidade | 53,7% | 43,2% | -10,6 p.p. |

Receita por usina:

| Usina | Antes (R$) | Depois (R$) | Diferença (R$) | Principal causa |
|-------|-----------:|------------:|---------------:|-----------------|
| UTE Bagaço Campo Real | 214.743.055 | 44.706.840 | -170.036.215 | Planilha de 10/05 digitada em kWh (-170,0 mi); PLD acima do teto (-25,8 mil) |
| UTE Gás Norte | 86.800.697 | 86.628.970 | -171.727 | Geração lançada durante a manutenção |
| UHE Campo Real Iguaçu | 218.630.889 | 218.571.430 | -59.459 | Vírgula deslocada, valor x10 (-105,8 mil); PLD negativo corrigido (+46,3 mil) |
| EOL Coxilha Real | 32.102.202 | 32.046.266 | -55.937 | Pico de leitura de 499 MWh (-62,8 mil); PLD negativo corrigido (+6,9 mil) |
| UFV Campo Real Minas | 19.563.885 | 19.544.047 | -19.838 | Dia 20/01 duplicado |
| UHE Tocantins Real | 86.156.194 | 86.156.194 | 0 | As 6 horas sem leitura já não somavam nada |
| PCH Rio das Araucárias | 28.867.985 | 28.872.463 | +4.479 | PLD negativo corrigido (+7,9 mil); duplicadas manuais (-3,4 mil) |
| UFV Sertão do Sol | 23.148.120 | 23.155.999 | +7.879 | PLD do Nordeste de 18/05 recuperado (+28,3 mil); solar de noite (-20,5 mil) |
| EOL Ventos do Potiguar | 98.062.381 | 98.137.672 | +75.291 | PLD do Nordeste de 18/05 recuperado |
| **Total** | **808.075.408** | **637.819.882** | **-170.255.526** | |

## 4. Conclusão

- **24 linhas** (um dia de uma usina digitado em kWh) respondem por quase
  toda a diferença: R$ 170 milhões de receita que não existe.
- Sem a limpeza, a diretoria veria a usina de biomassa como a segunda maior
  receita da empresa. Depois da limpeza ela é a quinta.
- Regras simples de campo vazio não pegariam esse erro: ele só aparece
  comparando a energia com a **potência da usina** (regra de acurácia).
- Recomendações: bloquear no sistema de medição energia maior que a
  potência e energia negativa; criar chave única (usina, hora) na tabela
  de medição; exigir unidade (MWh) no lançamento manual; monitorar usina
  sem dado há mais de 24 horas.
