# docs/plans/

Planos de tarefa escritos por Opus/Fable (nuvem) para o executor local implementar.

## Fluxo

1. Sessão normal do Claude Code (Opus/Fable) planeja e salva aqui: `<tarefa>.md`.
2. `bin/claude-local` (ou o workspace `vscode/executor.code-workspace`) abre o executor.
3. Prompt único: "implemente docs/plans/<tarefa>.md".
4. Revisão obrigatória do diff completo antes de commit → lições para
   `knowledge/lessons.md` (fluxo de realimentação, ver README raiz).

O plano é o contrato: escopo fechado, restrições explícitas verificáveis e critério de
aceite objetivo — é dele que o executor recupera contexto após uma compactação.

## Template de plano

    # <tarefa>

    ## Convenções aplicáveis
    <copiar daqui as regras relevantes de knowledge/conventions/<projeto>.md —
    o executor local segue melhor o que está DENTRO do plano do que o que
    precisa buscar. Antes de implementar módulos que você não conhece, consulte
    a tool search_knowledge sobre convenções e decisões (ADRs) do módulo afetado.
    Para documentação externa/atual de bibliotecas, use search_web e fetch_page
    (MCP web) — a WebSearch nativa não funciona no modelo local.>

    ## Escopo
    <o que entra e — explicitamente — o que NÃO entra>

    ## Restrições
    <imperativas e verificáveis no diff: "não usar X", "não tocar em Y">

    ## Passos
    <numerados, pequenos>

    ## Critério de aceite
    <comando que deve rodar / testes que devem passar>
