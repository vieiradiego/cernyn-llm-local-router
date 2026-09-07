# Prompts de handoff — planejamento (nuvem) → execução (local)

## Prompt 1 — para a sessão de PLANEJAMENTO (Fable/Opus, extensão ou claude normal)

Colar no Claude Code aberto no repo-alvo, ajustando a tarefa:

---

Você vai planejar uma tarefa que será EXECUTADA POR OUTRO MODELO — um Qwen3.8-27B
rodando localmente, classe Sonnet em coding agêntico, mas que segue pior instruções
implícitas e some com partes do escopo sem avisar. O plano é o único contrato dele.

Tarefa: <descreva aqui a tarefa real — pequena, uma unidade coerente, ex.: "corrigir
o bug X", "adicionar o endpoint Y", "cobrir o módulo Z com testes">

Escreva o plano em docs/plans/<NN>-<slug>.md seguindo exatamente esta estrutura:

1. **Convenções aplicáveis** — copie do CLAUDE.md e do conhecimento do projeto as
   regras que esta tarefa toca. Se houver a tool MCP search_knowledge disponível,
   consulte-a e inclua o que for relevante. Regras imperativas e verificáveis no diff.
2. **Escopo** — o que entra e, EXPLICITAMENTE, o que não entra.
3. **Restrições** — proibições verificáveis ("não usar sleep", "não tocar no arquivo
   X", "não alterar a API pública"). O executor local viola restrições implícitas;
   torne-as explícitas.
4. **Passos** — numerados, pequenos, cada um com resultado observável. Nada de
   "refatore conforme necessário": o executor não pode decidir arquitetura.
5. **Critério de aceite** — o comando exato que deve passar (testes, build, lint) e
   o que o diff final deve e não deve conter.

Regras do plano: sem decisões em aberto, sem "avaliar se", sem alternativas — decida
tudo agora. Se a tarefa for grande demais para ~30 min de execução focada, corte o
escopo e diga o que ficou de fora. NÃO implemente nada: só o plano.

---

## Prompt 2 — para a sessão de EXECUÇÃO (bin/claude-local, no mesmo repo)

    (na extensão, escolha o regime com /model: qwen3.8-27b · qwen3.8-27b-low · qwen3.8-27b-nothink)
    Implemente docs/plans/<NN>-<slug>.md. Siga o plano à risca: escopo, restrições e
    passos na ordem. Ao terminar, rode o critério de aceite e mostre o resultado.
    Se algo do plano não funcionar, PARE e relate — não replaneje.

## Durante a execução — o que medir (evals/results.md)

- **Intervenções**: cada vez que você precisou destravar/corrigir o agente (anote o motivo)
- **Loop**: mesma chamada falhando ~3x → interrompa (não-convergência)
- **Ao final**: critério de aceite passou? `git diff` completo — violações de restrição?
  escopo abandonado sem aviso?
- Duração total e, se possível, tok/s (logs do LM Studio)

## Depois — fechar o ciclo

1. Lições da revisão → `knowledge/lessons.md`
2. `python3 mcp/index.py` (reindexa)
3. Linha nova em `evals/results.md`
