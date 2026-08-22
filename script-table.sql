-- =====================================================================
-- StockSense — Schema consolidado (MySQL 8.0)
--
-- ATENÇÃO: ESTE ARQUIVO É DERIVADO. NÃO É A FONTE DA VERDADE.
--
-- A fonte da verdade do schema são as migrations Flyway do backend:
--     code/backend/src/main/resources/db/migration/
--         V1__create_schema.sql        (DDL inicial)
--         V2__seed_dados_padrao.sql    (seed de fallback)
--         V3__add_dias_ate_ruptura.sql (produto.dias_ate_ruptura)
--
-- É o Flyway que cria e versiona o banco quando a aplicação sobe. Este
-- script é a consolidação daquelas migrations em um único arquivo, para
-- leitura, documentação do TCC e criação manual do banco fora do Docker.
--
-- Ao alterar o schema: crie uma migration V4__... no backend e regenere
-- este arquivo. Nunca edite só aqui — a divergência não seria detectada.
--
-- Última sincronização: V3 (2026-08-22)
-- =====================================================================

-- O Flyway conecta a um banco já existente (o docker-compose cria via
-- MYSQL_DATABASE=stocksense), então estas duas linhas não estão em V1.
-- Existem apenas para execução manual deste script.
CREATE DATABASE IF NOT EXISTS stocksense
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;
USE stocksense;

-- =====================================================================
-- DDL — consolidação de V1 + V3
-- =====================================================================

-- ---------------------------------------------------------------------
-- estabelecimento — também guarda a credencial de acesso (login do MVP).
-- Decisão: login no nível do estabelecimento, sem tabela usuario no MVP.
-- ---------------------------------------------------------------------
CREATE TABLE estabelecimento (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    nome_fantasia VARCHAR(100) NOT NULL,
    cnpj          VARCHAR(18),
    endereco      VARCHAR(200),
    email         VARCHAR(100) NOT NULL,
    senha_hash    VARCHAR(255) NOT NULL,        -- bcrypt/argon2 (gerado pelo backend)
    CONSTRAINT uq_estabelecimento_email UNIQUE (email)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- produto — produto_id é chave natural definida pelo gestor, não
-- AUTO_INCREMENT (ver Guia de Importação). estabelecimento_id tem
-- DEFAULT 1 como preparação para multi-estabelecimento.
-- ---------------------------------------------------------------------
CREATE TABLE produto (
    produto_id             INT PRIMARY KEY,
    estabelecimento_id     INT            NOT NULL DEFAULT 1,
    nome                   VARCHAR(100)   NOT NULL,
    estoque_atual          INT            NOT NULL,
    categoria              VARCHAR(50),
    unidade_medida         VARCHAR(10),
    preco_custo            DECIMAL(10, 2),
    preco_venda            DECIMAL(10, 2),
    nivel_servico_alvo     DECIMAL(5, 2)  DEFAULT 0.95,
    -- campos calculados pelo motor preditivo — nunca recebidos via planilha --
    classe_abc             CHAR(1),
    desvio_padrao_demanda  DECIMAL(10, 4),
    ponto_reposicao        DECIMAL(10, 2),
    estoque_seguranca      DECIMAL(10, 2),
    dias_ate_ruptura       DECIMAL(10, 2),      -- V3: NULL enquanto o motor não rodou
    data_ultimo_calculo    DATETIME,
    CONSTRAINT fk_produto_estabelecimento
        FOREIGN KEY (estabelecimento_id) REFERENCES estabelecimento (id)
        ON DELETE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- fornecedor — fornecedor_id é chave natural. Sem estabelecimento_id:
-- a lista é global no MVP.
-- ---------------------------------------------------------------------
CREATE TABLE fornecedor (
    fornecedor_id INT PRIMARY KEY,
    nome          VARCHAR(100) NOT NULL,
    contato       VARCHAR(50)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- produto_fornecedor — lead time real por produto/fornecedor (N:N).
-- Os DEFAULTs cobrem o caso em que o lojista não envia a planilha 4.
-- ---------------------------------------------------------------------
CREATE TABLE produto_fornecedor (
    produto_id              INT            NOT NULL,
    fornecedor_id           INT            NOT NULL,
    lead_time_medio         INT            DEFAULT 3,
    variabilidade_lead_time DECIMAL(10, 4) DEFAULT 1.0,
    PRIMARY KEY (produto_id, fornecedor_id),
    CONSTRAINT fk_pf_produto
        FOREIGN KEY (produto_id) REFERENCES produto (produto_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_pf_fornecedor
        FOREIGN KEY (fornecedor_id) REFERENCES fornecedor (fornecedor_id)
        ON DELETE CASCADE
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- venda — histórico (planilha 5; mínimo 90 dias).
-- Dado de histórico => ON DELETE RESTRICT.
-- ---------------------------------------------------------------------
CREATE TABLE venda (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    produto_id     INT            NOT NULL,
    data_hora      DATETIME       NOT NULL,
    quantidade     INT            NOT NULL,
    valor_venda    DECIMAL(10, 2),
    is_promocional SMALLINT       DEFAULT 0,
    CONSTRAINT fk_venda_produto
        FOREIGN KEY (produto_id) REFERENCES produto (produto_id)
        ON DELETE RESTRICT,
    INDEX idx_venda_produto_data (produto_id, data_hora)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- previsao — APENAS os pontos diários da projeção (30 linhas por
-- execução). O motor mensal acumula (append): a "rodada atual" é o
-- maior executado_em. As métricas dos modelos ficam em metrica_modelo.
-- ---------------------------------------------------------------------
CREATE TABLE previsao (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    produto_id          INT            NOT NULL,
    data_previsao       DATE           NOT NULL,
    quantidade_prevista DECIMAL(10, 2),
    modelo_utilizado    VARCHAR(50),               -- vencedor (denormalizado p/ o gráfico)
    executado_em        DATETIME       NOT NULL,
    CONSTRAINT fk_previsao_produto
        FOREIGN KEY (produto_id) REFERENCES produto (produto_id)
        ON DELETE CASCADE,
    INDEX idx_previsao_produto_exec (produto_id, executado_em),
    INDEX idx_previsao_produto_data (produto_id, data_previsao)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- metrica_modelo — 2 linhas por execução (Holt-Winters e Prophet).
-- Fonte da Tela 10 (comparativo) e do KPI de acurácia do dashboard.
-- ---------------------------------------------------------------------
CREATE TABLE metrica_modelo (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    produto_id   INT          NOT NULL,
    modelo       VARCHAR(50)  NOT NULL,            -- 'holt_winters' | 'prophet'
    mape         DECIMAL(8, 4),
    rmse         DECIMAL(10, 4),
    mae          DECIMAL(10, 4),
    selecionado  BOOLEAN      NOT NULL DEFAULT FALSE,
    executado_em DATETIME     NOT NULL,
    CONSTRAINT fk_metrica_produto
        FOREIGN KEY (produto_id) REFERENCES produto (produto_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_metrica UNIQUE (produto_id, modelo, executado_em),
    INDEX idx_metrica_produto_exec (produto_id, executado_em)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

-- =====================================================================
-- DML — seed de fallback (V2)
--
-- Usado pelo backend quando o lojista não envia as planilhas desejáveis
-- (1_estabelecimento, 3_fornecedores, 4_produto_fornecedor).
-- INSERT IGNORE garante idempotência: re-executar não gera erro.
-- =====================================================================

-- ATENÇÃO: credencial de DESENVOLVIMENTO LOCAL apenas — email:
-- admin@stocksense.local, senha: admin123 (hash BCrypt abaixo). NUNCA usar
-- este valor em ambiente compartilhado, staging ou produção — trocar por
-- hash gerado no cadastro real.
INSERT IGNORE INTO estabelecimento (id, nome_fantasia, email, senha_hash)
    VALUES (1, 'StockSense Padrão', 'admin@stocksense.local', '$2a$10$ismpcFwGGZWgu9Df1MVmyeE9V00haDVPtIM66rmt2k9SQ9..515K6');

INSERT IGNORE INTO fornecedor (fornecedor_id, nome)
    VALUES (1, 'Fornecedor Padrão');
