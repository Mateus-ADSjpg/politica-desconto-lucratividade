

DROP TABLE IF EXISTS stg_superstore;

CREATE TABLE stg_superstore (
    row_id          TEXT,
    order_id        TEXT,
    order_date      TEXT,
    ship_date       TEXT,
    ship_mode       TEXT,
    customer_id     TEXT,
    customer_name   TEXT,
    segment         TEXT,
    country_region  TEXT,
    city            TEXT,
    state_province  TEXT,
    postal_code     TEXT,
    region          TEXT,
    product_id      TEXT,
    category        TEXT,
    sub_category    TEXT,
    product_name    TEXT,
    sales           TEXT,
    quantity        TEXT,
    discount        TEXT,
    profit          TEXT
);

COMMENT ON TABLE stg_superstore IS
    'Carga bruta do CSV Sample Superstore (Kaggle). Todas as colunas em TEXT. Nao consultar direto — usar vendas.';


DROP TABLE IF EXISTS vendas;

CREATE TABLE vendas (
    id_linha        INTEGER      PRIMARY KEY,
    id_pedido       VARCHAR(20)  NOT NULL,
    data_pedido     DATE         NOT NULL,
    data_envio      DATE         NOT NULL,
    modo_envio      VARCHAR(20)  NOT NULL,
    id_cliente      VARCHAR(10)  NOT NULL,
    nome_cliente    VARCHAR(60)  NOT NULL,
    segmento        VARCHAR(15)  NOT NULL,
    pais            VARCHAR(20)  NOT NULL,
    cidade          VARCHAR(40)  NOT NULL,
    estado          VARCHAR(30)  NOT NULL,
    cep             VARCHAR(10),
    regiao          VARCHAR(10)  NOT NULL,
    id_produto      VARCHAR(20)  NOT NULL,
    categoria       VARCHAR(20)  NOT NULL,
    subcategoria    VARCHAR(20)  NOT NULL,
    nome_produto    VARCHAR(150) NOT NULL,
    valor_venda     NUMERIC(10,4) NOT NULL,
    quantidade      INTEGER      NOT NULL,
    desconto        NUMERIC(4,2) NOT NULL,
    lucro           NUMERIC(10,4) NOT NULL,

    -- campos derivados
    faixa_desconto  VARCHAR(15),
    margem_pct      NUMERIC(8,2),
    dias_entrega    INTEGER,

    CONSTRAINT ck_desconto   CHECK (desconto BETWEEN 0 AND 1),
    CONSTRAINT ck_quantidade CHECK (quantidade > 0),
    CONSTRAINT ck_envio      CHECK (data_envio >= data_pedido)
);

COMMENT ON TABLE vendas IS
    'Vendas tratadas do Superstore. 1 linha = 1 item dentro de um pedido.';
COMMENT ON COLUMN vendas.faixa_desconto IS
    'Agrupamento do desconto em faixas de negocio, usado na analise do ponto de virada da margem.';
COMMENT ON COLUMN vendas.margem_pct IS
    'lucro / valor_venda * 100. Negativa quando a venda da prejuizo.';



CREATE INDEX idx_vendas_data       ON vendas (data_pedido);
CREATE INDEX idx_vendas_desconto   ON vendas (desconto);
CREATE INDEX idx_vendas_subcat     ON vendas (subcategoria);
CREATE INDEX idx_vendas_cliente    ON vendas (id_cliente);
