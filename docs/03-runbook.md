# 03 — Runbook

## Dia a dia

| Situação | Ação |
|---|---|
| Começar a trabalhar (dev) | LM Studio aberto → `bin/serve.sh` — **perfil dev**: só BGE-M3 residente; o Qwen entra via JIT no primeiro `/model`. Descarrega Gemma e variantes extras se encontrar |
| Instalar do zero / desfazer | `./install.sh` (`--dry-run` para ver) · `./uninstall.sh` |
| Testar o roteador isolado | `tests/smoke.sh` (30 s, sem modelos) |
| Rodar um replay de eval | `ENGINE=gguf evals/run.sh <TAREFA> <low|nothink|base> [turnos] [min]` — worktree limpa, executor no llama.cpp, aceite com testes de referência |
| Expediente do bot | `bin/serve.sh --atendimento` — carrega e aquece o Gemma. **Não** combinar com desenvolvimento pesado |
| Usar o modelo local na extensão | `/model qwen3.8-27b-low` (ou `-nothink`, `qwen3.8-27b`) — primeira resposta 1–2 min (prefill), depois rápido |
| Voltar para a nuvem | `/model claude-fable-5-1` |
| Ver o que está carregado | `lms ps` ou `curl -s localhost:1234/v1/models` |
| Depois de editar `knowledge/` ou `docs/plans/` | `python3 mcp/index.py` (incremental) |
| Guarda de memória (instalado, 30 s) | automático — `tail /tmp/local-llm-memguard.log`; notificação no macOS quando age |
| Após reboot | roteador sobe sozinho (LaunchAgent); LM Studio via serviço headless; `bin/serve.sh` (BGE) ou `--atendimento` (BGE + Gemma) |

## Ciclo de uma tarefa com o executor local

1. **Planejar (nuvem)** — Prompt 1 de `plans/PROMPT-HANDOFF.md`, tarefa pequena (~30 min).
2. **Executar (local)** — `/model qwen3.8-27b-low`, Prompt 2.
3. **Revisar** — `git diff` completo; contar intervenções; interromper em loop (~3 repetições).
4. **Fechar o ciclo** — lição em `knowledge/lessons.md`, linha em `evals/results.md`,
   `python3 mcp/index.py`.

Guarda-corpos (de medição pública, local vs. nuvem no mesmo plano: 74 vs. 114 testes,
7 vs. 1 intervenções, 32 violações de restrição): nunca deixar o local planejar/replanejar;
uma tarefa por sessão; revisão obrigatória; detector de não-convergência; em horário de
atendimento, tarefas longas de código vão para a nuvem (contenção de GPU).

## Escolha do regime de raciocínio

| `/model` | Quando |
|---|---|
| `qwen3.8-27b-nothink` | edições triviais, renomes, boilerplate — o mais rápido |
| `qwen3.8-27b-low` | executar planos — equilíbrio |
| `qwen3.8-27b` | depuração difícil — raciocínio máximo, **minutos por turno** |

Só uma variante fica na memória; a troca é automática (LM Studio JIT, ~7 s). A primeira
mensagem após a troca pode receber um erro que o Claude Code re-envia sozinho.

## Troubleshooting

| Sintoma | Causa provável | Ação |
|---|---|---|
| `API Error: 500 … tokens to keep … greater than the context length` | prompt maior que 119.552 tokens (conversa longa, ou connectors ligados sem a opção C) | conversa nova; confirmar `ROUTER_SANITIZE_LOCAL=1` no plist; ou guardrail → *medium* e `lms load … -c 200000` |
| 500 idem, **intermitente**, com retentativas que passam | concorrência de requisições de tamanhos díspares (não reproduzido em laboratório) | ignorar (Claude Code re-tenta); se frequente, mesmo remédio acima |
| `router: upstream … indisponível` (502) em **toda** sessão, nuvem inclusive | roteador caiu | `launchctl kickstart -k gui/$(id -u)/com.local-llm.router`; log `/tmp/local-llm-router.log` |
| Modelo local não responde / 400 "model not found" | LM Studio fechado ou modelo não carregado e JIT falhou por memória | abrir LM Studio; `lms ps`; descarregar variante irmã (`lms unload …`) |
| `lms` pendurado em "Waking up LM Studio service…" | app fechado sem serviço headless | abrir o app ou habilitar o serviço (Settings → Developer) |
| Resposta do Qwen vazia / só "pensando" por minutos | variante `qwen3.8-27b` (xhigh) | usar `-low`/`-nothink` |
| Gemma lento na 1ª resposta (~27 s) | compilação Metal | esperado; `serve.sh` faz warmup |
| Mac quente/ventoinha | conferir `ps aux \| sort -rk3 \| head`; em 05/09 eram 2 abas do Chrome a 100 %+ CPU, não a stack | Chrome → Gerenciador de tarefas |
| `modelo:2` aparece em `lms ps` | `lms load` repetido | `lms unload modelo:2` |
| Qwen "sumiu" (`/model` recarrega em ~7 s) | memguard descarregou por memória (ver log) | normal; se frequente, baixar `--parallel` ou fechar Chrome |
| **Memória disparando (>48 GB), sistema travando** | 2 variantes do Qwen residentes (uma explícita + uma JIT) e/ou Gemma residente em sessão dev | `lms ps`; `lms unload` do que sobra; **nunca** `lms load` manual do Qwen; usar `serve.sh` (perfil dev). Ver D12 |
| Extensão ignora o roteador | settings alterado sem reload | Developer: Reload Window |
| Executor repete o mesmo comando dezenas de vezes ("requires approval") | comando fora da allowlist (`--allowedTools`); o modelo local não muda de estratégia diante da negação | interromper; adicionar o padrão à allowlist (ex.: `Bash(npm install:*)`) e relançar |

## Verificações rápidas

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H 'x-api-key: x' localhost:4000/v1/models   # 200 = roteador
curl -s localhost:1234/v1/models | python3 -c 'import json,sys;[print(m["id"]) for m in json.load(sys.stdin)["data"]]'
lms ps                                   # carregados, contexto, parallel, TTL
launchctl print gui/$(id -u)/com.local-llm.router | grep state
tail -f /tmp/local-llm-router.log        # cada requisição: destino, status, modelo, tamanho
ls -t ~/.lmstudio/server-logs/2026-*/ | head -1   # log do LM Studio (corpo das requisições)
```

## Desfazer tudo

1. Apagar `claudeCode.environmentVariables` do user settings do VS Code (ou restaurar o backup).
2. `launchctl bootout gui/$(id -u)/com.local-llm.router && rm ~/Library/LaunchAgents/com.local-llm.router.plist`.
3. `claude mcp remove -s user web && claude mcp remove -s user knowledge`.
4. Modelos: `lms unload --all` e apagar `~/.lmstudio/models/local-llm/` (variantes) se quiser.
