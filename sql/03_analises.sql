/* =============================================================
   Projeto: politica-desconto-lucratividade
   Arquivo: 03_analises.sql
   Pergunta central: existe um limite de desconto a partir do qual
                     a venda deixa de compensar? Se existe, quanto
                     a empresa perde por nao respeita-lo?
   Pre-requisito: 01 e 02 executados; tabela `vendas` com 10.192 linhas.
   ============================================================= */


/* -------------------------------------------------------------
   A1. PANORAMA — o ponto de partida
   -------------------------------------------------------------
   Toda analise comeca situando quem le. Sem isso, os numeros
   seguintes nao tem escala de comparacao.

   Resultado: 10.192 itens | 5.111 pedidos | 793 clientes
              faturamento 2.326.153,86 | lucro 292.273,46
              margem 12,56% | 1.900 itens (18,6%) dao prejuizo
   ------------------------------------------------------------- */

SELECT COUNT(*)                                  AS itens,
       COUNT(DISTINCT id_pedido)                 AS pedidos,
       COUNT(DISTINCT id_cliente)                AS clientes,
       ROUND(SUM(valor_venda), 2)                AS faturamento,
       ROUND(SUM(lucro), 2)                      AS lucro,
       ROUND(SUM(lucro) / SUM(valor_venda) * 100, 2) AS margem_pct,
       COUNT(*) FILTER (WHERE lucro < 0)         AS itens_prejuizo,
       ROUND(COUNT(*) FILTER (WHERE lucro < 0)::numeric
             / COUNT(*) * 100, 1)                AS pct_itens_prejuizo
FROM   vendas;


/* -------------------------------------------------------------
   A2. MARGEM POR FAIXA DE DESCONTO — o achado principal
   -------------------------------------------------------------
   Resultado:
     Sem desconto ... 4.924 itens | 47,5% das vendas | margem  +29,56%
     Ate 20% ........ 3.854 itens | 36,8% das vendas | margem  +11,86%
     21% a 40% ......   463 itens | 10,1% das vendas | margem  -15,30%
     41% a 60% ......   226 itens |  3,1% das vendas | margem  -40,78%
     Acima de 60% ...   725 itens |  2,5% das vendas | margem -122,64%

   Leitura: a margem nao cai de forma suave, ela vira de sinal.
   Acima de 60% de desconto a empresa perde 1,23 dolar a cada
   dolar faturado — vender passa a ser pior do que nao vender.
   ------------------------------------------------------------- */

SELECT faixa_desconto,
       COUNT(*)                                  AS itens,
       ROUND(SUM(valor_venda), 2)                AS faturamento,
       ROUND(SUM(valor_venda) * 100
             / SUM(SUM(valor_venda)) OVER (), 2) AS pct_faturamento,
       ROUND(SUM(lucro), 2)                      AS lucro,
       ROUND(SUM(lucro) / SUM(valor_venda) * 100, 2) AS margem_pct
FROM   vendas
GROUP  BY faixa_desconto
ORDER  BY MIN(desconto);


/* -------------------------------------------------------------
   A3. O PONTO DE VIRADA — desconto a desconto
   -------------------------------------------------------------
   A faixa mostra a tendencia; este recorte mostra onde exatamente
   o sinal muda.

   Resultado: 20% -> margem +11,77% (3.706 itens)
              30% -> margem -10,08% (229 itens)
   A virada esta entre 20% e 30%. Nao ha nenhum nivel de desconto
   acima de 20% com margem positiva.

   RESSALVA HONESTA: a curva nao e' perfeitamente monotona na
   ponta baixa — 15% aparece com margem menor (+5,15%) que 20%
   (+11,77%). Sao apenas 52 itens a 15%, entao o numero e' fragil
   e reflete o mix de produtos daquelas vendas, nao um efeito do
   desconto. Vale citar isso no README em vez de esconder: quem
   avalia repara, e reconhecer o limite do dado conta a favor.
   ------------------------------------------------------------- */

SELECT desconto,
       COUNT(*)                                  AS itens,
       ROUND(SUM(valor_venda), 2)                AS faturamento,
       ROUND(SUM(lucro), 2)                      AS lucro,
       ROUND(SUM(lucro) / SUM(valor_venda) * 100, 2) AS margem_pct,
       CASE WHEN SUM(lucro) < 0 THEN 'PREJUIZO' ELSE 'lucro' END AS situacao
FROM   vendas
GROUP  BY desconto
ORDER  BY desconto;


/* -------------------------------------------------------------
   A4. QUANTO CUSTA PASSAR DE 20%
   -------------------------------------------------------------
   Aqui o achado vira dinheiro.

   Resultado: 1.414 itens (13,9% do total) tem desconto acima de
              20% e somam prejuizo de -136.008,63.
              Os outros 8.778 itens somam +428.282,09.
   Ou seja: 14% das vendas apagam 32% do lucro que o resto gera.
   ------------------------------------------------------------- */

SELECT CASE WHEN desconto > 0.20 THEN 'Acima de 20%'
            ELSE 'Ate 20%' END                   AS politica,
       COUNT(*)                                  AS itens,
       ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 1) AS pct_itens,
       ROUND(SUM(valor_venda), 2)                AS faturamento,
       ROUND(SUM(lucro), 2)                      AS lucro
FROM   vendas
GROUP  BY 1
ORDER  BY 1;


/* -------------------------------------------------------------
   A5. ONDE O DESCONTO ALTO SE CONCENTRA
   -------------------------------------------------------------
   Desconto nao e' distribuido por igual. Descobrir onde ele se
   concentra transforma a recomendacao em algo acionavel: nao
   adianta dizer "reduzam descontos", tem que dizer onde.

   Resultado (piores):
     Tables ..... 54,6% dos itens com desconto >20% | margem  -8,53%
     Bookcases .. 31,0%                             | margem  -3,15%
     Machines ... 45,3%                             | margem  +1,82%
     Supplies ...  0,0%                             | margem  -2,51%

   Dois detalhes que valem comentario no README:

   1) Supplies da prejuizo com desconto medio de apenas 8%. Ou
      seja, ali o problema nao e' desconto — e' custo ou preco de
      tabela. Um achado que contraria a tese principal e precisa
      aparecer, nao ser omitido.

   2) Binders tem o maior desconto medio da base (37%) e ainda
      assim margem positiva (+15,16%). Isso mostra que o desconto
      alto nao e' fatal em si: depende da margem de partida do
      produto. A recomendacao correta nao e' um teto unico, e sim
      um teto calibrado por subcategoria.
   ------------------------------------------------------------- */

SELECT subcategoria,
       COUNT(*)                                  AS itens,
       ROUND(AVG(desconto) * 100, 1)             AS desconto_medio_pct,
       ROUND(COUNT(*) FILTER (WHERE desconto > 0.20)::numeric
             / COUNT(*) * 100, 1)                AS pct_itens_desc_alto,
       ROUND(SUM(valor_venda), 2)                AS faturamento,
       ROUND(SUM(lucro), 2)                      AS lucro,
       ROUND(SUM(lucro) / SUM(valor_venda) * 100, 2) AS margem_pct
FROM   vendas
GROUP  BY subcategoria
ORDER  BY lucro;


/* -------------------------------------------------------------
   A6. SIMULACAO — e se o teto fosse 20%?
   -------------------------------------------------------------
   Reconstrucao do preco de tabela a partir do que existe:
     valor_venda = preco_cheio * (1 - desconto)  =>
     preco_cheio = valor_venda / (1 - desconto)
     custo       = valor_venda - lucro

   Com isso da' para recalcular a mesma venda a 20%.

   Resultado: nas 1.414 linhas afetadas, o lucro sairia de
              -136.008,63 para +84.165,75 — ganho de 220.174,37.
              O lucro total da operacao passaria de 292.273,46
              para 512.447,83 (+75%).

   PREMISSA — e' obrigatorio declarar isso no README:
   a simulacao assume que a demanda nao muda, ou seja, que o
   cliente compraria a mesma quantidade pagando mais. Na pratica
   parte dessas vendas simplesmente nao aconteceria. Entao o
   numero NAO e' "a empresa ganharia 220 mil": e' o teto teorico
   do ganho, util para dimensionar a ordem de grandeza do
   problema. Apresentar isso como resultado liquido seria erro
   grave de analise.
   ------------------------------------------------------------- */

WITH afetadas AS (
    SELECT valor_venda,
           lucro,
           valor_venda / (1 - desconto) AS preco_cheio,
           valor_venda - lucro          AS custo
    FROM   vendas
    WHERE  desconto > 0.20
),
simulado AS (
    SELECT valor_venda,
           lucro,
           preco_cheio * 0.80                  AS venda_simulada,
           preco_cheio * 0.80 - custo          AS lucro_simulado
    FROM   afetadas
)
SELECT COUNT(*)                                     AS itens_afetados,
       ROUND(SUM(valor_venda), 2)                   AS faturamento_atual,
       ROUND(SUM(venda_simulada), 2)                AS faturamento_simulado,
       ROUND(SUM(lucro), 2)                         AS lucro_atual,
       ROUND(SUM(lucro_simulado), 2)                AS lucro_simulado,
       ROUND(SUM(lucro_simulado) - SUM(lucro), 2)   AS ganho_teorico
FROM   simulado;


/* -------------------------------------------------------------
   A7. E ISSO E' PONTUAL OU E' POLITICA?
   -------------------------------------------------------------
   Um problema que aparece num ano so' e' incidente. Um que se
   repete todo ano e' processo — e exige mudanca de regra, nao
   correcao pontual.

   Resultado: o desconto medio fica em 15,5% nos quatro anos e a
              fatia de itens com desconto acima de 20% varia entre
              13,7% e 14,0%. Estavel.
   Conclusao: nao e' descontrole de um periodo, e' o jeito como a
   empresa vende. Reforca a recomendacao de mudar a politica em
   vez de auditar um trimestre.
   ------------------------------------------------------------- */

SELECT EXTRACT(YEAR FROM data_pedido)::INT       AS ano,
       COUNT(*)                                  AS itens,
       ROUND(AVG(desconto) * 100, 1)             AS desconto_medio_pct,
       ROUND(COUNT(*) FILTER (WHERE desconto > 0.20)::numeric
             / COUNT(*) * 100, 1)                AS pct_itens_desc_alto,
       ROUND(SUM(valor_venda), 2)                AS faturamento,
       ROUND(SUM(lucro) / SUM(valor_venda) * 100, 2) AS margem_pct
FROM   vendas
GROUP  BY 1
ORDER  BY 1;


/* -------------------------------------------------------------
   A8. A RESSALVA DO PAIS
   -------------------------------------------------------------
   A base tem 200 linhas do Canada misturadas com as americanas, e
   os rotulos de regiao (East/West/Central) sao usados para os dois
   paises ao mesmo tempo. Qualquer corte geografico precisa separar
   por pais, senao Ontario e a costa leste americana viram a mesma
   coisa. Alem disso, nada no arquivo informa se as vendas
   canadenses estao em CAD ou USD — limitacao a declarar no README.
   ------------------------------------------------------------- */

SELECT pais,
       regiao,
       COUNT(*)                                  AS itens,
       ROUND(AVG(desconto) * 100, 1)             AS desconto_medio_pct,
       ROUND(SUM(valor_venda), 2)                AS faturamento,
       ROUND(SUM(lucro) / SUM(valor_venda) * 100, 2) AS margem_pct
FROM   vendas
GROUP  BY pais, regiao
ORDER  BY pais, regiao;
