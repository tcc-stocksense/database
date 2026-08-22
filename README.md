# 🛒 Motor de Otimização Preditiva de Estoque

> Sistema de previsão de demanda e gestão de estoque para pequenos e médios mercados de bairro.  
> TCC — Sistemas de Informação · 2026

![Status](https://img.shields.io/badge/status-em%20desenvolvimento-yellow)
![Python](https://img.shields.io/badge/Python-3.10+-blue)
![Kotlin](https://img.shields.io/badge/Kotlin-Spring%20Boot-orange)
![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1)
![Licença](https://img.shields.io/badge/licença-acadêmica-lightgrey)

---

## 📋 Sobre o Projeto

Mercados de bairro independentes gerenciam estoque manualmente ou por intuição, gerando dois problemas recorrentes: **ruptura de estoque** (produto acaba antes da reposição) e **desperdício de perecíveis**. Este sistema aplica modelos de séries temporais para prever a demanda por produto, calcular automaticamente o ponto de reposição e gerar alertas acionáveis para o gestor — sem exigir perfil técnico.

---

## 👥 Equipe

| Nome | RA |
|---|---|
| Gabriel Boos Duarte | 03231030 |
| Gabriel Sanchez | 03231004 |
| Danilo Silvestre Faustino | 03231045 |
| Pedro Primon | 0323014 |
| Pedro Paulo Pinto | 0323015 |

---

## 🏗️ Arquitetura (C4 Nível 2)

```
┌─────────────────────────────────────────────┐
│             Motor Preditivo de Estoque       │
│                                             │
│  ┌──────────┐    ┌──────────┐    ┌───────┐  │
│  │  Web App │───▶│    API   │───▶│ AI/ML │  │
│  │HTML/CSS/JS    │  Kotlin  │    │Service│  │
│  └──────────┘    │Spring Boot    │Python │  │
│                  └──────┬───┘    └───┬───┘  │
│                         │            │      │
│                  ┌──────▼────────────▼───┐  │
│                  │       MySQL 8.0        │  │
│                  └───────────────────────┘  │
└─────────────────────────────────────────────┘
```

| Camada | Tecnologia | Responsabilidade |
|---|---|---|
| **Web App** | HTML / CSS / JS | Interface de upload, dashboards e alertas |
| **API** | Kotlin + Spring Boot | Orquestrador: valida dados, aciona IA, persiste resultados |
| **AI/ML Service** | Python + FastAPI | Motor preditivo: Holt-Winters vs Prophet, métricas MAPE/RMSE/MAE |
| **Banco de Dados** | MySQL 8.0 | Histórico de vendas, previsões, pontos de reposição |

---

## 🗄️ Modelagem de Dados

O banco possui **7 tabelas** organizadas em três grupos funcionais.

> ⚠️ **Fonte da verdade:** o schema é criado e versionado pelas **migrations Flyway**
> em `code/backend/src/main/resources/db/migration/`. O `script-table.sql` deste
> repositório é a consolidação delas em arquivo único, para leitura e criação
> manual do banco. Toda alteração entra como uma nova migration `V4__...` no
> backend; o script é então regenerado.

> 📄 **Documentação visual:** [`README_ModelagemDados.html`](README_ModelagemDados.html)  
> Abre no navegador — campos, propósito, relacionamentos e índices.
> **Pendente de atualização:** ainda descreve o modelo original (com
> `perda_estoque` e `venda_perdida_estimada`), anterior às migrations.

### Visão geral das tabelas

| Tabela | Função | Destaque |
|---|---|---|
| `estabelecimento` | Identidade de cada mercadinho | Também guarda a credencial de acesso (`email` + `senha_hash`) — login no nível do estabelecimento no MVP |
| `produto` | Catálogo + resultados do motor | `produto_id` é chave natural do gestor, não auto-incremento. Guarda `ponto_reposicao`, `estoque_seguranca` e `dias_ate_ruptura` calculados |
| `fornecedor` | Contatos de fornecedores | Lista global no MVP (sem vínculo por estabelecimento) |
| `produto_fornecedor` | Relação N:N com lead times | `lead_time_medio` alimenta a fórmula do PR; `DEFAULT 3` cobre quem não envia a planilha 4 |
| `venda` | Série temporal de vendas | Maior volume — indexada para o motor de IA |
| `previsao` | Pontos diários da projeção | Só a série prevista (30 linhas/execução); o motor acumula por `executado_em` |
| `metrica_modelo` | Acurácia por modelo | 2 linhas por execução (Holt-Winters e Prophet) — fonte do comparativo e do KPI de acurácia |

> A tabela `perda_estoque` foi **removida** do schema: o módulo ESG ficou fora do
> escopo do MVP. A coluna `venda.venda_perdida_estimada` também saiu — o KPI de
> ruptura é calculado por coeficiente ABRAS no frontend, sem persistência.

### Fórmulas centrais

Conforme implementadas em `code/ml-service/app/services/stock_service.py`:

```
Estoque de Segurança  = Z × √(LT × σ²_demanda + demanda² × σ²_lead_time)
Ponto de Reposição    = Demanda_média_diária × LT + Estoque_Segurança
Dias até Ruptura      = Estoque_atual ÷ Demanda_média_diária
```

- **Estoque de Segurança** usa a fórmula composta, que incorpora também a
  variabilidade do lead time (`σ_lead_time`) — buffer mais preciso que a versão
  simples `Z × σ_demanda × √LT`, que ignora atrasos irregulares do fornecedor.
  `Z` vem do `nivel_servico_alvo` do produto (default 0,95).
- **Dias até Ruptura** mede quantos dias o estoque atual suporta até chegar a
  zero — não até atingir o ponto de reposição. Retorna `NULL` quando a demanda
  média é zero ou negativa (divisão por zero; semanticamente, o produto não
  rompe com a demanda observada).

### Índices de performance

Declarados inline no `CREATE TABLE` (não como `CREATE INDEX` avulso):

```sql
-- Query principal do motor de IA (série temporal por produto)
INDEX idx_venda_produto_data (produto_id, data_hora)          -- em venda

-- Rodada atual da projeção e leitura do gráfico
INDEX idx_previsao_produto_exec (produto_id, executado_em)    -- em previsao
INDEX idx_previsao_produto_data (produto_id, data_previsao)   -- em previsao

-- Comparativo de modelos (Tela 10) e KPI de acurácia
INDEX idx_metrica_produto_exec (produto_id, executado_em)     -- em metrica_modelo
```

---

## 🤖 Modelos Preditivos

Dois modelos são implementados e comparados empiricamente:

| Modelo | Tipo | Vantagem no contexto |
|---|---|---|
| **Holt-Winters** | Suavização exponencial tripla | Baseline robusto, baixo custo computacional |
| **Prophet** | Aditivo com regressores externos | Lida melhor com sazonalidade e feriados; aceita `is_promocional` como regressor |

**Métricas de avaliação:** MAPE · RMSE · MAE

---

## 📊 KPIs do Sistema

| KPI | O que mede | Persona |
|---|---|---|
| Índice de Ruptura | Frequência de produto zerado com demanda ativa | Gestor |
| Giro de Estoque | Velocidade de renovação do estoque | Gestor |
| Acurácia Preditiva (MAPE) | Erro do modelo vs demanda real | Equipe técnica |
| Classificação ABC | Representatividade no faturamento | Gestor |
| Estoque de Segurança | Reserva contra variações e atrasos | Sistema |
| Dias até Ruptura | Alerta proativo de reposição | Funcionário |

> **Fora do escopo do MVP:** o KPI de *Redução de Desperdício* dependia da tabela
> `perda_estoque`, removida do schema junto com o módulo ESG.

---

## 🚨 Como funciona o alerta "Repor em X dias"

```
MySQL               Python (FastAPI)         Kotlin (Spring Boot)      Frontend
    │                      │                         │                     │
    │── série temporal ───▶│                         │                     │
    │── desvio_padrão ────▶│── calcula PR e dias ──▶│                     │
    │── lead_time ────────▶│── retorna JSON ────────▶│── persiste em       │
    │                      │                         │   produto/previsao  │
    │                      │                         │── GET /alertas ────▶│
    │                      │                         │                     │── 🟡 Banana: 15 dias
```

`dias_ate_ruptura` é persistido em **`produto`** (migration V3), não em `previsao`:
os alertas e o dashboard precisam do valor em lote, para ordenar por urgência e
contar `<= 7` / `< 3` dias.

---

## 📁 Estrutura do Repositório

O TCC está dividido em **três repositórios**. Este é o `database`:

```
database/                        ← este repositório (modelagem)
├── README.md                    ← este arquivo
├── README_ModelagemDados.html   ← documentação visual do banco
├── script-table.sql             ← schema consolidado (derivado das migrations)
├── der-diagram.mwb              ← DER (MySQL Workbench)
└── der-diagram.bak

code/                            ← aplicação
├── backend/                     ← Kotlin / Spring Boot
│   └── src/main/resources/db/migration/   ← FONTE DA VERDADE do schema
├── ml-service/                  ← Python / FastAPI (motor preditivo)
├── frontend/                    ← HTML / CSS / JS
└── docker-compose.yml

docs/                            ← documentação acadêmica
```

---

## 🗓️ Cronograma

| Fase | Período | Marco |
|---|---|---|
| **1 — Planejamento** | Fev – Abr 2026 | BD modelado · parceiro confirmado ✅ |
| **2 — Dados** | Abr – Jun 2026 | Dataset tratado · módulo entrada/saída |
| **3 — Motor** | Jun – Ago 2026 | Motor preditivo · comparação de modelos |
| **4 — Interface** | Ago – Set 2026 | Sistema integrado · validado com parceiro |
| **5 — Validação** | Set – Out 2026 | Artigo do TCC · indicadores de impacto |

---

## 📚 Principais Referências

- HYNDMAN, R. J.; ATHANASOPOULOS, G. *Forecasting: Principles and Practice*. 3. ed. OTexts, 2021.
- TAYLOR, S. J.; LETHAM, B. Forecasting at scale. *The American Statistician*, v. 72, n. 1, p. 37–45, 2018.
- BALLOU, R. H. *Gerenciamento da cadeia de suprimentos*. 5. ed. Porto Alegre: Bookman, 2006.
- SEBRAE. *Ideia de Negócio: Mercearia*. Brasília: Sebrae, 2023.
- Corporación Favorita Grocery Sales Forecasting — [Kaggle Dataset](https://www.kaggle.com/c/favorita-grocery-sales-forecasting)