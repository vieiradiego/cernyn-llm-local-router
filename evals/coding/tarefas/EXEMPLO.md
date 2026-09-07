# EXEMPLO — <título do card> (modelo de tarefa para o harness)

Repo: `<repo-alvo>` (stack, versão, restrições globais em uma linha).
Card original: Tipo · Prioridade · Área · Status. Replay (com gabarito) ou tarefa viva.

## Convenções aplicáveis
<copiar de knowledge/conventions/<repo>.md as regras que o executor precisa respeitar>

## Problema (do card)
<o que está errado ou faltando, do ponto de vista de quem usa>

## Escopo
**Entra**: <lista curta>. **Não entra**: <o que o executor NÃO deve tocar>.

## Restrições (verificáveis no diff)
- Não editar `<pastas proibidas>` (o harness confere via FORBIDDEN).
- Não fazer commit.

## Passos
1. <passo pequeno e verificável>
2. <inclua o "como": versão da lib, flag do instalador, trecho de config — o modelo local erra o que não sabe do projeto>

## Critério de aceite
- `npm run check` e `npm run build` verdes.
- Testes de referência (replay) ou ACCEPT_CMD (tarefa viva) passando.
