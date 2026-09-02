

-- 1.1 A carga trouxe tudo?  Resultado: 10194 linhas.
SELECT COUNT(*) AS linhas_carregadas FROM stg_superstore;

-- 1.2 Alguma data fora do padrao M/D/AAAA?  Resultado: nenhuma.
SELECT order_date, ship_date
FROM   stg_superstore
WHERE  order_date !~ '^\d{1,2}/\d{1,2}/\d{4}$'
   OR  ship_date  !~ '^\d{1,2}/\d{1,2}/\d{4}$';

-- 1.3 Algum numero que nao converte?  Resultado: nenhum.
SELECT row_id, sales, quantity, discount, profit
FROM   stg_superstore
WHERE  sales    !~ '^-?\d+(\.\d+)?$'
   OR  quantity !~ '^-?\d+$'
   OR  discount !~ '^-?\d+(\.\d+)?$'
   OR  profit   !~ '^-?\d+(\.\d+)?$';

-- 1.4 CEP com zero a esquerda.
--     Resultado: 1 CEP (05401, Burlington/VT) em 11 linhas.
--     Como INTEGER viraria 5401 e essas 11 linhas apontariam para
--     um endereco inexistente. Por isso a coluna e' VARCHAR.
SELECT postal_code, COUNT(*) AS linhas
FROM   stg_superstore
WHERE  postal_code LIKE '0%'
GROUP  BY postal_code
ORDER  BY linhas DESC;

-- 1.5 Linhas duplicadas, ignorando o row_id.
--     O row_id e' sequencial e unico por construcao, entao incluir
--     ele na comparacao esconderia qualquer duplicata. A chave real
--     do negocio e' pedido + produto + valores.
--     Resultado: 2 grupos duplicados.
SELECT COUNT(*) AS duplicadas
FROM  (SELECT order_id, product_id, sales, quantity, discount, profit,
              COUNT(*) AS n
       FROM   stg_superstore
       GROUP  BY 1,2,3,4,5,6
       HAVING COUNT(*) > 1) d;

-- 1.6 Um pedido pode ter varias linhas (itens). Confirmando a
--     granularidade: 1 linha = 1 item, nao 1 pedido.
SELECT COUNT(*)                        AS linhas,
       COUNT(DISTINCT order_id)        AS pedidos,
       ROUND(COUNT(*)::numeric
             / COUNT(DISTINCT order_id), 2) AS itens_por_pedido
FROM   stg_superstore;

-- 1.7 Olhando as duplicatas de perto antes de decidir o que fazer.
--     Retorna 4 linhas (2 pares). Em cada par os row_id sao
--     consecutivos (391/392 e 1699/1700) e todos os demais campos
--     sao identicos ate a quarta casa decimal do lucro.
--     Interpretacao: lancamento duplicado, nao venda repetida — se
--     o cliente pedisse o mesmo item duas vezes no mesmo pedido, o
--     sistema somaria na quantidade em vez de criar outra linha.
SELECT *
FROM   stg_superstore
WHERE  (order_id, product_id, sales, quantity, discount, profit) IN (
         SELECT order_id, product_id, sales, quantity, discount, profit
         FROM   stg_superstore
         GROUP  BY 1,2,3,4,5,6
         HAVING COUNT(*) > 1)
ORDER  BY order_id, row_id::INTEGER;


/* -------------------------------------------------------------
   2. CARGA DA TABELA FINAL
   -------------------------------------------------------------
   Duas decisoes tomadas aqui:

   a) TO_DATE com mascara explicita 'MM/DD/YYYY'. Sem isso o
      Postgres usa o datestyle da sessao e 3/1/2023 pode virar
      3 de janeiro ou 1 de marco dependendo da maquina. Esse tipo
      de bug nao da erro — so da numero errado.

   b) Deduplicacao via ROW_NUMBER(). A funcao numera as linhas
      dentro de cada grupo de duplicatas, ordenadas por row_id, e
      o WHERE rn = 1 mantem apenas a primeira ocorrencia.
      Descarta 2 linhas de 10194 (0,02%), equivalentes a R$ 380,49
      em vendas. Impacto irrelevante nos totais, mas mantem a
      contagem de itens por pedido correta.
   ------------------------------------------------------------- */

TRUNCATE TABLE vendas;

INSERT INTO vendas (
    id_linha, id_pedido, data_pedido, data_envio, modo_envio,
    id_cliente, nome_cliente, segmento, pais, cidade, estado,
    cep, regiao, id_produto, categoria, subcategoria, nome_produto,
    valor_venda, quantidade, desconto, lucro,
    faixa_desconto, margem_pct, dias_entrega
)
SELECT
    row_id::INTEGER,
    order_id,
    TO_DATE(order_date, 'MM/DD/YYYY'),
    TO_DATE(ship_date,  'MM/DD/YYYY'),
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country_region,
    city,
    state_province,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales::NUMERIC,
    quantity::INTEGER,
    discount::NUMERIC,
    profit::NUMERIC,

    -- faixa de desconto: os cortes seguem o que o negocio pratica
    CASE
        WHEN discount::NUMERIC = 0     THEN 'Sem desconto'
        WHEN discount::NUMERIC <= 0.20 THEN 'Ate 20%'
        WHEN discount::NUMERIC <= 0.40 THEN '21% a 40%'
        WHEN discount::NUMERIC <= 0.60 THEN '41% a 60%'
        ELSE                                'Acima de 60%'
    END,

    -- margem: NULLIF protege contra divisao por zero
    ROUND(profit::NUMERIC / NULLIF(sales::NUMERIC, 0) * 100, 2),

    TO_DATE(ship_date, 'MM/DD/YYYY') - TO_DATE(order_date, 'MM/DD/YYYY')

FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY order_id, product_id, sales, quantity,
                            discount, profit
               ORDER BY row_id::INTEGER
           ) AS rn
    FROM stg_superstore
) s
WHERE rn = 1;


/* -------------------------------------------------------------
   3. VALIDACAO POS-CARGA
   -------------------------------------------------------------
   Sempre confira os totais depois de transformar. Se o
   faturamento mudou alem do esperado entre staging e tabela
   final, alguma conversao comeu linha.
   ------------------------------------------------------------- */

SELECT COUNT(*)                    AS linhas,
       MIN(data_pedido)            AS primeira_venda,
       MAX(data_pedido)            AS ultima_venda,
       ROUND(SUM(valor_venda), 2)  AS faturamento,
       ROUND(SUM(lucro), 2)        AS lucro_total,
       ROUND(SUM(lucro) / SUM(valor_venda) * 100, 2) AS margem_geral_pct,
       COUNT(*) FILTER (WHERE lucro < 0)             AS linhas_prejuizo
FROM   vendas;

-- Esperado apos deduplicacao:
--   linhas ............ 10192   (10194 - 2 duplicatas)
--   periodo ........... 2023-01-03 a 2026-12-30
--   faturamento ....... 2.326.153,86
--   lucro_total ....... 292.273,46
--   margem_geral_pct .. 12,56
--   linhas_prejuizo ... 1900
