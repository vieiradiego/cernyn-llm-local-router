# 04 — Decisões (ADRs da stack)

Decisões sobre a própria stack `local-llm`, com contexto e evidência. (ADRs dos projetos-alvo
ficam em `knowledge/adr/` e são indexados pelo MCP `knowledge`.)

## D01 — "Frontier planeja, local executa" (31/08/2026)
**Decisão**: Fable/Opus fazem planejamento e revisão; o modelo local só implementa planos
escritos. **Evidência**: benchmark público (E2E Playwright/Laravel) — qualidade de plano 9,8
(Claude) vs 6,3 (Qwen3.6-27B); executando o mesmo plano, 74 vs 114 testes passando, 7 vs 1
intervenções, 32 violações de restrição. **Consequência**: guarda-corpos do runbook.

## D02 — Executor: Qwen3.8-27B 4-bit MLX (31/08/2026)
**Decisão**: `mlx-community/Qwen3.8-27B-4bit` em vez de Qwen3.6-27B ou Qwen3-Coder-Next.
**Evidência**: lançado 14/08/2026; SWE-bench Pro 61,7 % (vs 53,5 % do 3.6 e 44,3 % do
Coder-Next 80B-A3B); Apache 2.0; 262K de contexto; cabe (16 GB) junto do modelo de
atendimento. **Reavaliar**: dez/2026 (não há Coder do 3.8 ainda).

## D03 — Atendimento: Gemma 4 26B-A4B QAT (31/08/2026)
**Decisão**: MoE de 25,2B com 3,8B ativos, QAT 4-bit oficial. **Evidência**: MMLU Pro 82,6 %
vs 77,2 % do 12B denso, mais rápido por ativar menos parâmetros; 46 tok/s medidos; 140+
idiomas. **Descartado**: SABIÁ (Sabiá-3/4 API-only; Sabiá-7B com licença LLaMA-1, só pesquisa
— veta uso comercial). **Pendente**: eval PT-BR (rubrica em `evals/ptbr/`, P3B3 como base).

## D04 — Runtime: LM Studio com MLX (31/08/2026)
**Decisão**: LM Studio (não Ollama/llama.cpp). **Evidência**: MLX 40–80 % mais rápido no
Apple Silicon; endpoint `/v1/messages` nativo (Claude Code fala direto); serviço headless;
JIT/Auto-Evict/TTL nativos. **Custo**: sem autenticação → só `localhost`.

## D05 — Roteador local em vez de trocar de janela (06/09/2026)
**Decisão**: a extensão aponta para `router/router.py` (:4000) que decide pelo nome do
modelo. **Evidência**: com só `ANTHROPIC_BASE_URL`, o login OAuth sobrevive (nuvem 200 em 5 s)
e os connectors claude.ai continuam ativos; `/model` troca na mesma conversa. **Alternativas
rejeitadas**: workspace dedicado (duas janelas), env no `.claude/settings.json` (redirecionaria
o planejamento), claude-code-router (exige API key paga). **Risco aceito**: roteador caído
derruba toda sessão → LaunchAgent KeepAlive + vigias.

## D06 — Variantes de template para o regime de raciocínio (06/09/2026)
**Decisão**: `qwen3.8-27b-low` e `-nothink` como modelos separados (symlinks + template).
**Evidência**: o template liga thinking `xhigh` por padrão; LM Studio ignora todos os
parâmetros da API testados; na tarefa CPF+testes: xhigh >238 s sem resposta, low 57 s,
nothink 39 s. **Por que não mudar o default do template original**: preservar o comportamento
do fabricante como opção explícita.

## D07 — Sem ajustes "por baixo dos panos" (06/09/2026, decisão do usuário)
**Decisão**: o usuário escolhe o modelo e recebe o comportamento daquele modelo. Roteador
transparente por padrão; troca de variante fica com o LM Studio (JIT + Auto-Evict); padrão
dos scripts = `qwen3.8-27b`; nomes = identificadores do LM Studio (sem aliases).
**Revertido**: swap automático e cap de `max_tokens` no roteador (viraram opt-in).

## D08 — Opção C: remover tools dos connectors no caminho local (06/09/2026, decisão do usuário)
**Contexto**: a extensão envia 152 tools em toda sessão; 117 são dos connectors claude.ai
(Notion 42, Gmail 29, HubSpot 26, Drive 11, Calendar 9) ≈ 100K tokens. Nenhuma sessão cabia
nos 119K do Qwen — nem uma janela nova (500 "tokens to keep > context"). **Alternativas
oferecidas**: (A) desligar connectors via `/mcp` por sessão; (B) guardrail medium + contexto
200K. **Decisão**: (C) `ROUTER_SANITIZE_LOCAL=1` — remove **só** `mcp__claude_ai_*`, só no
caminho local; nuvem intacta; `knowledge` e `web` preservados; sem cap de `max_tokens`, sem
mexer em headers. **Evidência**: 534 KB → 154 KB, 200 OK nas requisições reais.

## D09 — Internet para o modelo local via MCP próprio (06/09/2026)
**Decisão**: `mcp/web_server.py` (DuckDuckGo via `ddgs` + `trafilatura`), sem chave, escopo
do usuário. **Evidência**: WebSearch nativa não funciona com o Qwen (depende da API Anthropic);
WebFetch funciona mas lenta; Qwen via roteador buscou e retornou 2 resultados reais em 91 s.

## D10 — Conhecimento por retrieval, nunca por treino (01/09/2026)
**Decisão**: camada 1 (CLAUDE.md, convenções, lições, ADRs) + camada 2 (MCP `knowledge`).
Nenhum fine-tuning sobre outputs do Claude (termos da Anthropic). Fine-tuning sobre código
próprio: só se as evals mostrarem falha recorrente que contexto não resolva.

## D11 — Laptop como servidor é estágio, não destino (31/08/2026)
Sleep, tampa, throttling (20–40 % após 10–15 min) e contenção dev × atendimento numa GPU.
Migrar o serving para um Mac mini/Studio quando o atendimento tiver volume real.

## D12 — Perfis de memória: Qwen só via JIT, Gemma só sob demanda (06/09/2026, pós-incidente)
**Incidente**: LM Studio chegou a ~72 GB de "memória" numa máquina de 48 GB e travou o sistema
(swap foi a 9,2 GB). **Causa** (server-log + roteador): `-low` carregado *explicitamente* pelo
`serve.sh`/testes + `qwen3.8-27b` carregado por *JIT* quando o usuário o escolheu no `/model`
— o Auto-Evict do LM Studio só descarrega modelos JIT, então os dois ficaram (32 GB) — mais o
Gemma residente (15,6 GB) e KV de requisições de ~40K tokens em até 4 slots (~2,5 GB cada).
**Decisão**: `serve.sh` nunca carrega o Qwen (fica 100 % por conta do JIT, que troca sozinho);
perfil **dev** (padrão) mantém só BGE-M3 residente e descarrega Gemma/variantes extras se
encontrar; perfil **`--atendimento`** carrega o Gemma. Healthcheck só recarrega o Gemma com o
perfil de atendimento ativo. **Regra**: nunca `lms load` manual de uma variante do Qwen. **Complemento**: o prompt cache store do engine MLX cresce sem teto útil em RAM (pico 31 GB com um Qwen) → guarda de memória `bin/memguard.sh` como LaunchAgent (D12b).

## D13 — Executor em llama.cpp (GGUF) para sessões agênticas longas (07/09/2026)
**Contexto**: dois replays de LUM-114 no engine MLX foram inválidos — o engine oscila 16→37 GB
a cada requisição longa (pico transitório do prefill + retenção de ~12 GB depois), o guarda de
memória descarregou o modelo 11× em 50 min e o executor nunca completou um turno. Medido num
prompt único de 90K tokens: MLX prefill 311 s, pico 37 GB, livre 10 %; GGUF UD-Q4_K_S no
llama.cpp (c=131072, parallel 1) prefill 634 s, RSS ~26 GB sem pico, livre 33 %; decode igual
(16,9 vs 17 tok/s). **Decisão**: sessões longas (harness de eval e execução de planos) rodam no
GGUF/llama.cpp — memória previsível vale mais que prefill 2× mais rápido; MLX fica para uso
interativo curto. Identificadores: `qwen3.8-27b-gguf`, `-gguf-low`, `-gguf-nothink` (variantes por
`bin/gguf-variant.sh`, pois a API não controla o thinking no llama.cpp tampouco). Guarda de
memória mantido (18 %/8 % livre, engine > 34 GB).

## D14 — Regime de raciocínio por tipo de tarefa (07/09/2026, evidência das evals)
**Evidência** (replays com gabarito, llama.cpp GGUF, autônomos, 0 intervenções):
- LUM-114 (débito de UI + JSON-LD): os três regimes passam 100 %; tempo nothink 15,5 min <
  low 36 min < xhigh 55 min.
- LUM-103 (bug P1, 7 arquivos, envolve fronteira client/server do Next.js): `nothink` acerta a
  lib (unit 19/19) mas chama um hook client num server component e não recupera no cap de 60
  turnos (build ✗); `low` cria o componente `"use client"` e entrega completo (68 min).
- LUM-111 (feature: tema claro + alternador + CSP): `nothink` passa 100 % em 23 min; `low`
  estoura o cap de 90 min sem construir o alternador (35 requisições, ~2,5 min/turno).
**Decisão**: padrão `qwen3.8-27b-gguf-nothink` (mais rápido; 2 de 3 tarefas completas); `-low`
quando a tarefa envolve decisão de arquitetura (fronteiras, estado, integração) — ciente de que
ele pode deliberar demais (LUM-111);
`base` (xhigh) só para depuração difícil — nas evals não trouxe ganho, só tempo. A escolha
continua explícita no `/model` (D07); o plano do Fable pode recomendar o regime no cabeçalho.
**Observação colateral** (LUM-128, run inválido por allowlist): ao receber "requires approval"
para `npm install`, o executor `nothink` repetiu o mesmo comando 32× até o cap. O modelo local
não trata negação como sinal para mudar de estratégia; o harness (e qualquer wrapper
autônomo) precisa de um detector de não-convergência — N tool calls idênticos consecutivos
abortam a sessão.
**Card vivo (LUM-128, a11y lint + Lefthook)**: nenhum regime entregou no cap de 60 turnos —
`nothink` 12,5 min (1/3 a11y, hooks ✗), `low` 56 min (lint+typecheck ✓, hooks ✗). Ambos
gastaram ~40 % dos turnos aprendendo tooling e ambos responderam ao ERESOLVE com
`--legacy-peer-deps`, que podou o `vite` e quebrou os testes. Conclusão: para cards que
exigem ferramentas novas, (a) o cap precisa ser maior ou o plano precisa trazer o "como"
(versão, flags, snippet de config) e (b) armadilhas de tooling do projeto devem entrar em
`knowledge/conventions/` — é exatamente o conhecimento que o retrieval existe para carregar.

## Hipóteses testadas e refutadas (para não reabrir)
- "Idioma PT-BR encarece muito": +10 % na entrada, raciocínio sai em inglês igual → marginal.
- "Prefill repetido é o gargalo": cache de prompt funciona (26 s → 1,8 s).
- "PARALLEL=4 divide o contexto e causa 500": 3 req concorrentes de 31K passaram; parallel=1
  é 3× mais lento.
- "Headers `anthropic-beta` quebram o LM Studio": aceitos (200).
- "`-c 200000` no `lms load` aumenta o contexto": ignorado pelo guardrail *high*.
- "`defaultContextLength: 8192` limita cargas JIT via API": não (119.552 medido).
