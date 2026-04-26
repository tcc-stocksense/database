# 🛒 Motor de Otimização Preditiva de Estoque

> Sistema de previsão de demanda e gestão de estoque para pequenos e médios mercados de bairro.  
> TCC — Sistemas de Informação · 2026

![Status](https://img.shields.io/badge/status-em%20desenvolvimento-yellow)
![Python](https://img.shields.io/badge/Python-3.11-blue)
![Kotlin](https://img.shields.io/badge/Kotlin-Spring%20Boot-orange)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-336791)
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
│                  │      PostgreSQL        │  │
│                  └───────────────────────┘  │
└─────────────────────────────────────────────┘
```

| Camada | Tecnologia | Responsabilidade |
|---|---|---|
| **Web App** | HTML / CSS / JS | Interface de upload, dashboards e alertas |
| **API** | Kotlin + Spring Boot | Orquestrador: valida dados, aciona IA, persiste resultados |
| **AI/ML Service** | Python + FastAPI | Motor preditivo: Holt-Winters vs Prophet, métricas MAPE/RMSE/MAE |
| **Banco de Dados** | PostgreSQL | Histórico de vendas, previsões, pontos de reposição |

---

## 🗄️ Modelagem de Dados

O banco possui **7 tabelas** organizadas em três grupos funcionais.

> 📄 **Documentação visual completa:** [`docs/README_ModelagemDados.html`](docs/README_ModelagemDados.html)  
> Abre no navegador — contém todos os campos, propósito de cada um, relacionamentos e índices.

### Visão geral das tabelas

| Tabela | Função | Destaque |
|---|---|---|
| `estabelecimento` | Identidade de cada mercadinho | Base do isolamento multi-tenant |
| `produto` | Catálogo + resultados do motor | Guarda `ponto_reposicao` e `dias_ate_ruptura` calculados |
| `fornecedor` | Contatos de fornecedores | Lista privada por estabelecimento |
| `produto_fornecedor` | Relação N:N com lead times | `lead_time_medio` alimenta a fórmula do PR |
| `venda` | Série temporal de vendas | Maior volume — indexada para o motor de IA |
| `perda_estoque` | Módulo ESG — rastreio de desperdício | Separa vencimento, avaria e furto |
| `previsao` | Resultados persistidos do Python | `dias_ate_ruptura` alimenta os alertas do dashboard |

### Fórmulas centrais

```
Estoque de Segurança  = Z × σ_demanda × √lead_time
Ponto de Reposição    = Demanda_média_diária × lead_time + Estoque_Segurança
Dias até Ruptura      = (Estoque_atual - Ponto_Reposição) ÷ Demanda_média_diária
```

### Índices de performance

```sql
-- Query principal do motor de IA (série temporal por produto)
CREATE INDEX idx_venda_produto_data
    ON venda(estabelecimento_id, produto_id, data_hora);

-- Endpoint de alertas do Spring Boot
CREATE INDEX idx_previsao_produto
    ON previsao(estabelecimento_id, produto_id, data_previsao);

-- Relatório ESG mensal
CREATE INDEX idx_perda_produto_data
    ON perda_estoque(produto_id, data_perda);
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
| Redução de Desperdício | Volume descartado por vencimento | ESG / Gestor |
| Dias até Ruptura | Alerta proativo de reposição | Funcionário |

---

## 🚨 Como funciona o alerta "Repor em X dias"

```
PostgreSQL          Python (FastAPI)         Kotlin (Spring Boot)      Frontend
    │                      │                         │                     │
    │── série temporal ───▶│                         │                     │
    │── desvio_padrão ────▶│── calcula PR e dias ──▶│                     │
    │── lead_time ────────▶│── retorna JSON ────────▶│── persiste previsao │
    │                      │                         │── GET /alertas ────▶│
    │                      │                         │                     │── 🟡 Banana: 15 dias
```

---

## 📁 Estrutura do Repositório

```
motor-estoque-tcc/
├── README.md                    ← este arquivo
├── docs/
│   └── README_ModelagemDados.html  ← documentação visual do banco
├── sql/
│   └── schema.sql               ← script completo do banco de dados
├── ai-service/                  ← Python / FastAPI
│   ├── main.py
│   ├── models/
│   │   ├── holt_winters.py
│   │   └── prophet_model.py
│   └── requirements.txt
├── api/                         ← Kotlin / Spring Boot
│   └── src/
└── web/                         ← HTML / CSS / JS
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