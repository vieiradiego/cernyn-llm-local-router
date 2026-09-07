# Evals do executor de código

3-5 tarefas **reais dos seus projetos**, cada uma como um plano já escrito por Opus/Fable —
é exatamente assim que elas chegarão em produção (protocolo de handoff via
`docs/plans/<tarefa>.md`). Tarefa sintética não mede o que importa.

## Como montar uma tarefa

1. Escolher uma tarefa pendente real (bug, feature pequena, refactor localizado).
2. Pedir ao Opus/Fable um plano de implementação e salvar em `tarefas/NN-<nome>.md`.
3. O plano deve conter **pelo menos uma restrição explícita e verificável**
   (ex.: "não usar sleep/waitForTimeout", "não tocar no arquivo X", "manter a API
   pública intacta") — aderência a restrição é o que separa os modelos.
4. Critério de aceite objetivo: testes que devem passar, comando que deve rodar.

## Protocolo de execução (por modelo × tarefa)

1. Branch limpa; `bin/serve.sh` de pé; modelo carregado há **≥ 15 min sob carga**
   (máquina fria mente — rodar um warmup de geração contínua antes).
2. `bin/claude-local` → "implemente evals/coding/tarefas/NN-<nome>.md".
3. Intervir só quando o agente travar; **cada intervenção é anotada** (o quê, por quê).
4. Interromper se repetir a mesma chamada falhando ~3 vezes (anotar como não-convergência).
5. Ao final: rodar o critério de aceite, revisar o `git diff` inteiro, contar violações
   de restrição e escopo abandonado.

## Métricas (registrar em results.md)

A métrica que decide é **intervenções por tarefa** — foi ela que separou local de nuvem na
medição pública (7 vs. 1), não tok/s.

| Métrica | Como medir |
|---|---|
| Intervenções | contagem manual, com motivo |
| Tarefa concluída | critério de aceite passou sem retoque humano |
| Violações de restrição | grep/inspeção no diff final |
| Escopo abandonado | itens do plano sem implementação e sem aviso |
| tok/s decode @ 1K e @ 64K | logs do LM Studio; a curva importa mais que o pico |
| Tempo de prefill @ 64K | idem |
| tok/s após 15 min de carga | mede o throttling real do chip Pro (esperado: -20-40%) |
| Compactações de contexto | contagem na sessão |

## Ordem do bake-off

1. `Qwen3.8-27B-4bit` (candidato principal) — todas as tarefas.
2. `Qwen3.8-27B-MTP-4bit` — 1 tarefa, só para validar suporte e medir ganho de velocidade.
3. Se (1) reprovar (>3 intervenções/tarefa em média, ou violações sistemáticas):
   `Devstral-Small-2`, depois `Qwen3-Coder-Next` em IQ4_XS (descarregar os outros modelos).


## Harness: `evals/run.sh` (replays com gabarito e tarefas vivas)

```sh
ENGINE=gguf evals/run.sh LUM-114 nothink 60 90   # tarefa, regime (nothink|low|base), max turnos, max minutos
```

- Lê `tarefas/<TAREFA>.md` (plano) e `tarefas/<TAREFA>.env` (`REPO`, `BASE_SHA`, `REF_SHA`,
  `ACCEPT_E2E`, `ACCEPT_UNIT`, `FORBIDDEN`, `ACCEPT_CMD`).
- **Isolamento**: a worktree é destacada (sem branch) e fica fora do repo-alvo, em
  `EVAL_ROOT` (padrão `~/.cache/local-llm/worktrees/<repo>`); é removida ao final — o que sobra
  é `diff.patch` nos resultados. `KEEP_WORKTREE=1` mantém para revisão. O repo-alvo não ganha
  branch, commit nem pasta.
- **Replay**: worktree limpa em `BASE_SHA` (commit pai do gabarito), `node_modules` por clone
  APFS (`cp -Rc`; symlink quebra o Turbopack), plano copiado para `docs/plans/`, executor via
  roteador (`claude -p`, `--output-format json`), depois `npm run check`, `npm run build` e os
  testes de referência copiados do `REF_SHA` (ocultos ao executor durante a execução).
- **Tarefa viva** (`REF_SHA` vazio): aceite pelo `ACCEPT_CMD` (shell na worktree, rc 0 = passou).
- Engine: `gguf` (llama.cpp, memória previsível — padrão) ou `mlx`. O harness carrega a variante
  do regime com `-c 131072 --parallel 1` e descarrega outras variantes do Qwen antes.
- Saída: `results/<TAREFA>-<regime>/` (`report.md`, `claude.json`, `diff.patch`, `check.log`,
  `build.log`, `e2e.log`, `mem.log`; diretório ignorado pelo git — contém código do projeto-alvo)
  e uma linha em `results/replays.md` (versionada).
- Métricas: turnos, duração, requisições/erros, diff, arquivos proibidos tocados, check, build,
  e2e de referência, pico de memória do engine, ações do memguard. Intervenções = 0 por
  construção (autônomo); a rodada interativa (A4) mede intervenções à parte.
