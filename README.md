# Política de desconto e lucratividade

**A partir de qual desconto a venda deixa de compensar — e quanto custa não respeitar esse limite?**

Análise em SQL sobre 10.192 itens vendidos entre 2023 e 2026, identificando o ponto em que
o desconto concedido passa a destruir margem e dimensionando o impacto financeiro dessa prática.

---

## Contexto

Uma rede varejista de material de escritório e mobiliário fecha o período com 12,56% de margem
sobre 2,33 milhões em faturamento. O número parece saudável, mas esconde um problema: **18,6% dos
itens vendidos dão prejuízo**. Quase um em cada cinco.

Descontos são a explicação mais provável, mas "dar menos desconto" não é recomendação — é palpite.
A pergunta útil é onde exatamente está o limite, quanto se perde por ultrapassá-lo, e em quais
produtos isso se concentra.

---

## Dados

| | |
|---|---|
| **Origem** | Sample Superstore (Kaggle) |
| **Volume** | 10.194 linhas brutas → 10.192 após tratamento |
| **Granularidade** | 1 linha = 1 item dentro de um pedido |
| **Período** | 03/01/2023 a 30/12/2026 |
| **Escopo** | 5.111 pedidos, 804 clientes, 17 subcategorias, EUA e Canadá |
| **Banco** | PostgreSQL 18 |

---

## Perguntas respondidas

1. Existe um nível de desconto a partir do qual a venda passa a dar prejuízo?
2. Quanto do lucro da operação é apagado pelas vendas acima desse nível?
3. Em quais subcategorias o desconto alto se concentra?
4. Qual seria o impacto de tornar esse limite obrigatório?
5. Isso é um descontrole pontual ou é a forma como a empresa vende?

---

## Como foi feito

**Carga em duas etapas.** O CSV entra numa tabela de staging com todas as colunas em `TEXT` e só
depois é convertido e tipado. A conversão vira uma etapa auditável em vez de falhar em silêncio
durante o import.

**Decisões de tipagem que importaram:**

- `cep` como `VARCHAR`, não `INTEGER`. A base contém 200 linhas canadenses com códigos postais
  alfanuméricos (`M7A`, `V6Z`, `H1A`). Como inteiro, a carga não teria acontecido — abortaria na
  primeira linha do Canadá.
- `desconto` e valores monetários como `NUMERIC`, não `FLOAT`. Ponto flutuante acumula erro de
  arredondamento em somas grandes.
- Datas convertidas com máscara explícita `MM/DD/YYYY`. Sem isso o resultado depende do
  `datestyle` da sessão — um bug que não dá erro, só dá número errado.

**Duplicatas.** Comparando por `pedido + produto + valores` (ignorando o `row_id`, que é sequencial
e mascararia qualquer repetição), apareceram 2 pares idênticos até a quarta casa decimal do lucro,
com `row_id` consecutivos. Interpretação: lançamento duplicado, não venda repetida — o sistema
somaria na quantidade em vez de criar outra linha. Removidos via `ROW_NUMBER()`, mantendo a primeira
ocorrência. Impacto: 0,02% das linhas, R$ 380,49 em vendas.

**Campos derivados** na carga: faixa de desconto, margem por item e prazo de entrega.

---

## Resultados

### 1. A margem não cai — ela vira de sinal

| Faixa | Itens | % do faturamento | Margem |
|---|---:|---:|---:|
| Sem desconto | 4.924 | 47,5% | **+29,56%** |
| Até 20% | 3.854 | 36,8% | **+11,86%** |
| 21% a 40% | 463 | 10,1% | −15,30% |
| 41% a 60% | 226 | 3,1% | −40,78% |
| Acima de 60% | 725 | 2,5% | **−122,64%** |

Acima de 60% de desconto, a empresa perde 1,23 dólar a cada dólar faturado. Vender passa a ser
pior do que não vender.

### 2. O limite é 20%, e é nítido

Analisando desconto a desconto, **nenhum nível acima de 20% apresenta margem positiva**. A 20% a
margem é +11,77%; a 30% já é −10,08%.

Mais revelador: 85% dos itens se concentram em apenas dois níveis — 0% e 20%. A empresa não negocia
caso a caso, opera com duas faixas padrão. E a segunda faixa padrão é exatamente o último nível
lucrativo. **A política vigente já está correta; o problema são as exceções acima dela.**

### 3. 14% das vendas apagam 32% do lucro

| | Itens | % | Lucro |
|---|---:|---:|---:|
| Até 20% | 8.778 | 86,1% | +428.282,09 |
| Acima de 20% | 1.414 | 13,9% | **−136.008,63** |

### 4. Onde se concentra

| Subcategoria | Desconto médio | % itens acima de 20% | Margem |
|---|---:|---:|---:|
| Tables | 26% | 54,6% | −8,53% |
| Bookcases | 22% | 31,0% | −3,15% |
| Machines | 30% | 45,3% | +1,82% |

**Dois resultados contrariam a tese principal e precisam ser ditos:**

- **Supplies** dá prejuízo (−2,51%) com desconto médio de apenas 8%. Ali o problema não é desconto,
  é custo ou preço de tabela — e nenhuma política de desconto resolve.
- **Binders** tem o maior desconto médio da base (37%) e ainda assim margem de +15,16%. Desconto
  alto não é fatal por si só: depende da margem de partida do produto.

Isso muda a recomendação. Um teto único de 20% penalizaria Binders sem necessidade e não resolveria
Supplies. O teto precisa ser calibrado por subcategoria.

### 5. É política, não incidente

O desconto médio fica em 15,5% nos quatro anos, e a fatia de itens acima de 20% varia entre 13,7% e
14,0%. Estável. Não é descontrole de um período — é a forma como a empresa vende, e exige mudança de
regra, não auditoria de trimestre.

### 6. Dimensionando o ganho

Recalculando as 1.414 vendas afetadas com teto de 20%, o lucro sairia de −136.008,63 para
+84.165,75.

**Esta simulação assume demanda constante** — que o cliente compraria a mesma quantidade pagando
mais. Na prática, parte dessas vendas não aconteceria. O número não é ganho esperado, é **teto
teórico**, útil apenas para dimensionar a ordem de grandeza do problema.

---

## Recomendações

1. **Tornar 20% um limite obrigatório**, não sugerido. A empresa já usa esse patamar como padrão;
   trata-se de fechar a exceção, não de criar regra nova.
2. **Calibrar o teto por subcategoria.** Binders sustenta desconto maior; Tables e Bookcases não
   sustentam o atual.
3. **Revisar Supplies fora da política de desconto** — o prejuízo ali tem outra causa.
4. **Exigir aprovação para descontos acima de 60%**, faixa que responde por 2,5% do faturamento e
   −70,8 mil de prejuízo.

---

## Limitações

- A simulação de teto assume demanda inelástica. Testar isso exigiria dado de elasticidade que a
  base não contém.
- A relação entre desconto e margem só é confiável a partir de 20%. Os níveis de 10% e 15% têm 96 e
  52 itens — amostra pequena demais, e a margem observada neles reflete mix de produto, não efeito
  de desconto.
- Os rótulos de região (East/West/Central) são usados para EUA e Canadá simultaneamente. Qualquer
  corte geográfico precisa separar por país.
- Não há indicação de moeda para as 200 linhas canadenses. Foram tratadas na mesma unidade das
  demais, o que pode distorcer os valores absolutos desse subconjunto.
- 804 IDs de cliente para 800 nomes distintos: agrupamentos por cliente devem usar o ID.

---

## O que eu faria diferente

- Trataria país como dimensão desde a modelagem, em vez de descobrir a mistura durante a análise.
- Buscaria o custo unitário em vez de derivá-lo de `venda − lucro`. A derivação funciona, mas
  impede separar problema de precificação de problema de custo — que é exatamente o caso de Supplies.
- Testaria faixas de desconto por subcategoria desde o início, em vez de assumir faixas globais e
  descobrir depois que elas não servem para todos os produtos.

---

## Reproduzindo

```bash
# 1. Criar o banco
createdb superstore

# 2. Executar na ordem
psql -d superstore -f sql/01_criacao_tabelas.sql

# 3. Carregar o CSV
psql -d superstore -c "\copy stg_superstore FROM 'dados/samplesuperstore.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"

# 4. Limpeza e análises
psql -d superstore -f sql/02_limpeza.sql
psql -d superstore -f sql/03_analises.sql
```

Testado em PostgreSQL 18. As consultas usam `FILTER (WHERE ...)` e funções de janela, que exigem
PostgreSQL 9.4 ou superior.
