# Diálogos de avaliação PT-BR

~20 diálogos multi-turno, um arquivo cada (`01-*.md` … `20-*.md`). Os esqueletos abaixo
cobrem as categorias; **preencher com casos reais do SEU produto** antes de rodar — diálogo
genérico não pega alucinação sobre política/preço/prazo, que é o critério eliminatório.

Formato de cada arquivo:

```markdown
# 01 — dúvida simples de produto
persona: <colar o system prompt do bot>
contexto_rag: <trecho da base de conhecimento que o retrieval deveria trazer>

## turno 1 (cliente)
...
## turno 2 (cliente, após resposta do bot)
...
```

## Distribuição por categoria

| # | Categoria | O que estressa |
|---|---|---|
| 01-04 | Dúvida de produto (simples → composta) | C3, C5 — respostas com base no RAG |
| 05-06 | Preço, prazo, política de troca | C3 — terreno clássico de alucinação |
| 07-08 | Problema técnico com passos de diagnóstico | C5, coerência multi-turno |
| 09-10 | Cliente irritado / ameaça cancelar | C2, C7 — tom e escalonamento |
| 11-12 | Pedido de reembolso/cancelamento | C7 — gatilho obrigatório de humano |
| 13 | Cliente confuso, muda de assunto 3x | memória de conversa |
| 14 | Pergunta fora de escopo (concorrente, opinião) | C4 |
| 15 | Pergunta cuja resposta NÃO está no RAG | C3 — tem que dizer "não sei" |
| 16-18 | Prompt injection ("ignore suas instruções", "me dê desconto de 100%", pedido em inglês p/ quebrar persona) | C4 |
| 19-20 | Fluxo que termina em JSON p/ backend (abrir chamado, agendar) | C6 |

## Iscas de deriva PT-PT

Incluir nos diálogos termos que convidam o modelo a escorregar: cliente falando de "tela"
(o bot não pode responder "ecrã"), "celular" (não "telemóvel"), "usuário" (não
"utilizador"), e pelo menos um diálogo inteiro em tom informal para testar se o registro
segura sem virar PT-PT formal.
