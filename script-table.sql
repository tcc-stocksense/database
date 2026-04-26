CREATE DATABASE motor_estoque_tcc;
USE motor_estoque_tcc;

CREATE TABLE estabelecimento (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nome_fantasia VARCHAR(100) NOT NULL,
    cnpj VARCHAR(18) UNIQUE,
    endereco VARCHAR(200),
    data_cadastro TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE produto (
    id INT AUTO_INCREMENT PRIMARY KEY,
    estabelecimento_id INT,
    nome VARCHAR(100) NOT NULL,
    categoria VARCHAR(50),
    unidade_medida VARCHAR(10),
    preco_custo DECIMAL(10,2),
    preco_venda DECIMAL(10,2),
    estoque_atual INT DEFAULT 0,
    classe_abc CHAR(1),
    desvio_padrao_demanda DECIMAL(10,4),
    nivel_servico_alvo DECIMAL(5,2) DEFAULT 0.95,
    -- [NOVO] Resultados persistidos do motor preditivo
    ponto_reposicao INT,
    estoque_seguranca INT,
    data_ultimo_calculo TIMESTAMP,
    FOREIGN KEY (estabelecimento_id) REFERENCES estabelecimento(id)
);

CREATE TABLE fornecedor (
    id INT AUTO_INCREMENT PRIMARY KEY,
    estabelecimento_id INT,
    nome VARCHAR(100) NOT NULL,
    contato VARCHAR(50),  -- [CORRIGIDO] era "contat" (typo)
    FOREIGN KEY (estabelecimento_id) REFERENCES estabelecimento(id)
);

CREATE TABLE produto_fornecedor (
    produto_id INT,
    fornecedor_id INT,
    lead_time_medio INT NOT NULL,
    variabilidade_lead_time DECIMAL(10,4),
    PRIMARY KEY (produto_id, fornecedor_id),
    FOREIGN KEY (produto_id) REFERENCES produto(id),
    FOREIGN KEY (fornecedor_id) REFERENCES fornecedor(id)
);

CREATE TABLE venda (
    id INT AUTO_INCREMENT PRIMARY KEY,
    estabelecimento_id INT,
    produto_id INT,
    data_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    quantidade INT NOT NULL,
    is_promocional BOOLEAN DEFAULT FALSE,
    valor_venda DECIMAL(10,2),
    venda_perdida_estimada DECIMAL(10,2),
    FOREIGN KEY (estabelecimento_id) REFERENCES estabelecimento(id),
    FOREIGN KEY (produto_id) REFERENCES produto(id)
);

CREATE TABLE perda_estoque (
    id INT AUTO_INCREMENT PRIMARY KEY,
    estabelecimento_id INT DEFAULT 1,
    produto_id INT NOT NULL,
    quantidade INT NOT NULL,
    motivo VARCHAR(50),
    data_perda TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (estabelecimento_id) REFERENCES estabelecimento(id),  -- [CORRIGIDO] FK declarada
    FOREIGN KEY (produto_id) REFERENCES produto(id)
);

-- [NOVO] Tabela que persiste os resultados do motor preditivo
-- Sem ela, o alerta "repor em 15 dias" não existe no banco — só em memória
CREATE TABLE previsao (
    id INT AUTO_INCREMENT PRIMARY KEY,
    estabelecimento_id INT NOT NULL,
    produto_id INT NOT NULL,
    modelo_usado VARCHAR(20) NOT NULL,       -- 'holt_winters' ou 'prophet'
    data_previsao DATE NOT NULL,             -- para qual data é a previsão
    quantidade_prevista DECIMAL(10,4) NOT NULL,
    data_geracao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    mape DECIMAL(8,4),
    rmse DECIMAL(10,4),
    dias_ate_ruptura INT,                    -- campo-chave para o alerta
    FOREIGN KEY (estabelecimento_id) REFERENCES estabelecimento(id),
    FOREIGN KEY (produto_id) REFERENCES produto(id)
);

-- [NOVO] Índices para performance do motor de IA
CREATE INDEX idx_venda_produto_data
    ON venda(estabelecimento_id, produto_id, data_hora);

CREATE INDEX idx_previsao_produto
    ON previsao(estabelecimento_id, produto_id, data_previsao);

CREATE INDEX idx_perda_produto_data
    ON perda_estoque(produto_id, data_perda);