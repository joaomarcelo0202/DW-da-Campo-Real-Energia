# Painel no Power BI

Arquivo: `painel_campo_real.pbix` (na raiz do projeto).

O painel lê **somente** do data warehouse `dw_campo_real`, nunca das tabelas de
origem. Os números de conferência estão no `sql/06_indicadores.sql`.

## 1. Conexão

- O Power BI lê o MariaDB pelo **MariaDB ODBC 3.2 Driver** (64 bits).
- A conexão usa três parâmetros (**Transformar dados > Editar parâmetros**):
  `Servidor` = `localhost`, `Porta` = `3306`, `BancoDW` = `dw_campo_real`.
- Credencial: **Banco de Dados**, usuário `root`, senha em branco (XAMPP).
  O Power BI pede uma vez por computador, na primeira atualização.
- Modo **Importar**: o `.pbix` guarda uma cópia dos dados. Depois de rodar o
  `python/rodar_tudo.py`, clicar em **Atualizar** para ler o banco de novo.

Tabelas importadas: `dim_tempo`, `dim_usina`, `dim_submercado`, `dim_parada`,
`fato_geracao`, `fato_pld`, `fato_clima`, `dq_metricas` e `dq_antes_depois`.

## 2. Relacionamentos

Todos de 1 para muitos, da dimensão para o fato, com filtro em uma direção:

| Dimensão | Fato | Coluna |
|----------|------|--------|
| dim_tempo | fato_geracao, fato_pld, fato_clima | sk_tempo |
| dim_usina | fato_geracao, fato_clima | sk_usina |
| dim_submercado | fato_geracao, fato_pld | sk_submercado |
| dim_parada | fato_geracao | sk_parada |

`dim_tempo[nome_mes]` é ordenado por `mes` e `nome_dia_semana` por
`dia_semana`. As chaves substitutas ficam escondidas.

## 3. Medidas (DAX)

```DAX
Geração (MWh) = CALCULATE(SUM(fato_geracao[energia_mwh]), KEEPFILTERS(fato_geracao[sk_usina] <> -1))
Fator de capacidade = DIVIDE([Geração (MWh)], SUM(fato_geracao[capacidade_mwh]))
Receita (R$) = SUM(fato_geracao[receita_rs])
Preço capturado (R$/MWh) = DIVIDE([Receita (R$)], [Geração (MWh)])
PLD médio (R$/MWh) = CALCULATE(AVERAGE(fato_pld[pld_rs_mwh]), KEEPFILTERS(dim_tempo[ano] = 2025))
PLD de referência (R$/MWh) = CALCULATE([PLD médio (R$/MWh)], TREATAS(VALUES(dim_usina[cod_submercado]), dim_submercado[cod_submercado]))
Razão de captura = DIVIDE([Preço capturado (R$/MWh)], [PLD de referência (R$/MWh)])
Horas paradas = CALCULATE(COUNTROWS(fato_geracao), KEEPFILTERS(fato_geracao[sk_parada] <> 0))
Energia não gerada (MWh) = CALCULATE(SUM(fato_geracao[energia_perdida_mwh]), KEEPFILTERS(fato_geracao[sk_parada] <> 0))
Receita não gerada (R$) = CALCULATE(SUM(fato_geracao[receita_perdida_rs]), KEEPFILTERS(fato_geracao[sk_parada] <> 0))
Índice de qualidade = 1 - DIVIDE(SUM(dq_metricas[registros_falha]), SUM(dq_metricas[registros_avaliados]))
```

O **PLD de referência** resolve o fato de o `fato_pld` não ter usina: ele pega
os submercados das usinas que estão no filtro (por exemplo, as usinas de uma
fonte) e calcula o PLD médio só desses submercados.

## 4. Páginas

Todas as páginas, menos a última, têm o filtro `ano = 2025`.

| Página | Pergunta | O que mostra | Valores esperados |
|--------|----------|--------------|-------------------|
| 1 Quanto geramos | 1 | Cartões de geração, fator de capacidade e geração sem cadastro; geração por usina, fonte, submercado e mês | 3,1 milhões de MWh; 43,2%; 1.845 MWh sem cadastro |
| 2-3 Quanto vale | 2 e 3 | Receita, preço capturado, PLD médio; receita por usina; tabela e gráfico de razão de captura por fonte | R$ 638 mi; R$ 204,51/MWh; térmica 1,25 e solar 0,76 |
| 4 Quando o PLD é alto | 4 | Mapa de calor hora x mês do PLD; perfil horário da solar e da eólica x PLD; preço capturado por patamar de carga | Pico das 17h às 21h e de agosto a dezembro |
| 5 Paradas | 5 | Horas paradas, energia e receita não geradas, por tipo, por usina e por parada | 1.672 horas; R$ 8,2 mi (R$ 7,5 mi programadas) |
| 6 Clima | 6 | Dispersão radiação x geração solar e vento x geração eólica | Correlação 0,93 a 0,94 (solar) e 0,23 a 0,26 (eólica) |
| 7 Podemos confiar | 7 | Índice de qualidade, falhas por dimensão, marcas de qualidade no fato, regras e decisões, receita antes e depois da limpeza | 99,96%; de R$ 808 mi para R$ 638 mi |

## 5. Conclusões que o painel mostra

1. A geração de 2025 vale R$ 637,8 milhões a PLD, e não os R$ 808 milhões que
   a conta sem limpeza mostrava.
2. A solar vende no pior horário (razão de captura 0,76); a térmica, que só
   liga na ponta, vende no melhor (1,25).
3. As manutenções de julho e agosto saíram caras; janeiro e fevereiro têm o
   PLD mais baixo do ano.
4. Poucas linhas erradas (24 lançadas em kWh) mudam muito o resultado: é
   preciso validar unidade e potência na entrada dos dados.

## 6. Créditos

PLD: CCEE - Dados Abertos (CC-BY 4.0). Clima: Open-Meteo (CC-BY 4.0).
Geração, usinas e paradas: dados fictícios da disciplina.
