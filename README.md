# Data Warehouse da Campo Real Energia

Trabalho prático de Data Warehouse. A partir do banco operacional da Campo Real
Energia (geradora fictícia com 9 usinas), o projeto extrai o preço da energia
(PLD) e o clima, mede a qualidade dos dados, limpa e carrega um star schema
para responder: **quanto a nossa geração vale, onde e quando ganhamos ou
perdemos dinheiro, e se dá para confiar nos números**.

## O que tem aqui

```
painel_campo_real.pbix  painel do Power BI (lê só do data warehouse)
config.exemplo.ini      modelo do arquivo de configuração
requirements.txt        bibliotecas Python
dados/pld/              CSV do PLD horário baixados do portal da CCEE (2025 e 2026)
python/
  banco.py              ler config, conectar no banco e gravar log
  01_extrair_pld.py     Etapa 1: PLD da CCEE (raw + tratada)
  02_extrair_clima.py   Etapa 1: clima da Open-Meteo (raw + tratada)
  03_qualidade.py       Etapa 2: profiling e regras de qualidade
  04_antes_depois.py    Etapa 2: indicadores antes x depois da limpeza
  rodar_tudo.py         roda o trabalho inteiro, do zero, na ordem certa
sql/
  00_campo_real_energia_original.sql   script da professora, sem mexer
  01_origem_criar.sql                  banco de origem (passos 0 a 4.4)
  02_tabelas_extracao.sql              tabelas e view da extração
  03_origem_problemas.sql              banco de origem (passos 5 e 6)
  04_dw_criar.sql                      Etapa 3: DDL do star schema
  05_dw_carga.sql                      Etapa 3: limpeza e carga do DW
  06_indicadores.sql                   Etapa 4: consultas dos indicadores
docs/
  modelagem.md            matriz de barramento, grão, diagrama e SCD
  relatorio_qualidade.md  problemas, quantidade, decisão e impacto
  painel_powerbi.md       páginas do painel, medidas DAX e valores esperados
```

## Requisitos

- **MariaDB 10.4** (o que vem no XAMPP) ou MySQL 8
- **Python 3.12**
- MySQL Workbench ou DBeaver para olhar os dados (opcional)
- Power BI Desktop para o painel
- **MariaDB ODBC 3.2 Driver (64 bits)**: é por ele que o Power BI lê o banco.
  Download em https://mariadb.com/downloads/connectors/ (ODBC connector, Windows)

### Banco escolhido

O enunciado permite MySQL ou PostgreSQL. Escolhemos o **MySQL**, usando o
servidor que já vem no XAMPP. Esse servidor é o MariaDB, que é compatível com
o MySQL e usa os mesmos comandos.

O script da professora foi feito para o MySQL 8 e tem duas linhas que o
MariaDB não aceita. Só essas duas foram ajustadas (o ajuste está comentado no
começo do `sql/01_origem_criar.sql`):

| No script original | Como ficou | Por quê |
|--------------------|------------|---------|
| `COLLATE utf8mb4_0900_ai_ci` | `COLLATE utf8mb4_general_ci` | essa collation só existe no MySQL 8 |
| `SET SESSION cte_max_recursion_depth = 10000;` | linha comentada | essa configuração só existe no MySQL 8 |

Nenhum dado mudou: o banco de origem fica com as mesmas 78.798 medições que o
script original gera.

## Configuração

1. Ligar o MySQL no painel do XAMPP.
2. Instalar as bibliotecas:
   ```
   pip install -r requirements.txt
   ```
3. Copiar `config.exemplo.ini` para `config.ini` e ajustar usuário, senha e
   porta do banco. O `config.ini` não vai para o Git.

## Como testar (um comando)

Com o MySQL do XAMPP ligado e o `config.ini` criado, rodar na pasta do projeto:

```
python python/rodar_tudo.py
```

O script apaga e recria os dois bancos, executa os 9 passos na ordem e mostra
uma conferência no final. Leva cerca de 1 minuto e deve terminar com:

```
Geração 2025: 3,118,741 MWh (esperado 3,118,741)
Receita 2025: R$ 637,819,881.98 (esperado 637,819,881.98)
```

Depois disso dá para olhar as tabelas no Workbench ou no DBeaver
(`localhost`, porta `3306`, usuário `root`) e abrir o painel.

## Abrir o painel

1. Abrir o `painel_campo_real.pbix` no Power BI Desktop. Ele já abre com os
   dados da última carga.
2. Para ler o banco de novo, clicar em **Página Inicial > Atualizar**.
3. Na primeira atualização em um computador novo o Power BI pede a
   credencial: escolher **Banco de Dados**, usuário `root` e senha em branco
   (padrão do XAMPP) e clicar em **Conectar**.

O painel tem 6 páginas, uma para cada pergunta da diretoria (geração, valor e
captura de preço, horas e meses de PLD alto, paradas, clima e confiança nos
números). Ele lê **somente** do schema `dw_campo_real`. Se o banco estiver em
outra porta ou servidor, mudar em **Transformar dados > Editar parâmetros**
(`Servidor`, `Porta` e `BancoDW`).

## Ordem de execução (passo a passo)

O `rodar_tudo.py` faz exatamente os passos abaixo. Para rodar um de cada vez,
os arquivos `.sql` podem ser executados no Workbench/DBeaver ou pela linha de
comando (na pasta do projeto):

| # | Comando | O que faz |
|---|---------|-----------|
| 1 | `mysql -u root < sql/01_origem_criar.sql` | cria o banco de origem `campo_real_energia` |
| 2 | `mysql -u root < sql/02_tabelas_extracao.sql` | cria a view do PLD, as tabelas do clima e o log |
| 3 | `python python/01_extrair_pld.py` | carrega o PLD 2025 e 2026 (raw e tratada) |
| 4 | `mysql -u root < sql/03_origem_problemas.sql` | passo 5 da professora: insere os problemas de qualidade |
| 5 | `python python/02_extrair_clima.py` | baixa o clima horário das 9 usinas |
| 6 | `mysql -u root < sql/04_dw_criar.sql` | cria o schema `dw_campo_real` |
| 7 | `python python/03_qualidade.py` | profiling e métricas de qualidade |
| 8 | `mysql -u root < sql/05_dw_carga.sql` | limpa os dados e carrega dimensões e fatos |
| 9 | `python python/04_antes_depois.py` | grava o antes x depois da limpeza |
| 10 | `mysql -u root --table < sql/06_indicadores.sql` | mostra os indicadores (conferência do painel) |

Cuidados:

- O passo 4 tem que vir **depois** do passo 3 (ele altera a tabela de PLD).
- Rodar o passo 3 de novo depois do passo 4 recarrega a tabela tratada a
  partir do raw e desfaz os problemas plantados no PLD. Para repetir o
  trabalho, comece do passo 1.
- No MySQL 8, antes do passo 8, tirar o comentário da linha
  `SET SESSION cte_max_recursion_depth` no começo do `05_dw_carga.sql`.

## Sobre a extração do PLD (o que aconteceu com a API)

O enunciado pede o PLD pela API do portal de dados abertos da CCEE. Nos nossos
testes a API e o link direto do CSV devolveram **"acesso bloqueado" (HTTP 403)**
para qualquer chamada feita por programa. A professora autorizou usar o arquivo
CSV. O processo ficou assim:

1. o script **tenta a API** (com paginação, tempo limite e novas tentativas);
2. a falha é **gravada na tabela `log_extracao`** (status `ERRO`, com a mensagem);
3. o script lê o **CSV do mesmo recurso**, baixado pelo navegador na página do
   conjunto de dados, e segue normalmente.

Se a API voltar a responder, o mesmo script passa a usar a API sem mudar nada.
A parte da API não pôde ser testada com sucesso justamente por causa do bloqueio.

O CSV de 2026 foi baixado em 13/11/2026 e vai até essa data.

## Resultados principais (2025)

| Indicador | Valor |
|-----------|-------|
| Geração | 3.118.741 MWh |
| Receita valorada ao PLD | R$ 637,8 milhões |
| Preço capturado | R$ 204,51/MWh |
| Fator de capacidade | 43,2% |
| Melhor razão de captura | Térmica a gás (1,25) |
| Pior razão de captura | Solar (0,76) |
| Receita não gerada por paradas | R$ 8,2 milhões |
| Diferença da receita com a limpeza | de R$ 808,1 mi para R$ 637,8 mi (-21%) |

## Fontes de dados

- **CCEE - Dados Abertos**, conjunto PLD_HORARIO, licença CC-BY 4.0.
  https://dadosabertos.ccee.org.br/dataset/pld_horario
- **Open-Meteo**, Historical Weather API, uso não comercial com atribuição
  (CC-BY 4.0). https://open-meteo.com/
- Limites do PLD: ANEEL, Despacho 3.625/2024 (2025) e Despacho 3.850/2025 (2026).
- Geração, usinas e paradas: dados fictícios do script da disciplina.
