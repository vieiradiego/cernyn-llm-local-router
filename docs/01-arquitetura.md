# 01 — Arquitetura

Stack de inferência local num MacBook Pro **M5 Pro, 18 núcleos, 48 GB** de memória unificada
(~307 GB/s), para dois workloads:

1. **Execução de desenvolvimento** — Fable/Opus (nuvem) planejam; um modelo local implementa
   a partir de um plano escrito. Princípio: *frontier planeja, local executa*.
2. **Atendimento a clientes em PT-BR** — modelo local de baixa latência (produto do bot ainda
   não construído; ver fase 7 no plano).

## Visão geral

```
                         VS Code + extensão Claude Code
                    (user settings: ANTHROPIC_BASE_URL → :4000)
                                      │
                                      ▼
                      ┌──────────────────────────────┐
                      │  router/router.py  :4000     │  LaunchAgent com.local-llm.router
                      │  decide pelo nome do modelo  │  (KeepAlive, sobe no login)
                      └──────┬─────────────────┬─────┘
             /model claude-* │                 │ /model qwen… | gemma…
                             ▼                 ▼
               api.anthropic.com       LM Studio  :1234  (engine MLX, Apple Silicon)
               (login claude.ai,        ├─ qwen3.8-27b{,-low,-nothink}  executor (JIT, 1 por vez)
                connectors, betas)      ├─ gemma-4-26b-a4b-it-qat        atendimento (residente)
                                        └─ text-embedding-bge-m3         embeddings (residente)
                                                   ▲
                    MCPs (escopo do usuário do Claude Code)
                    ├─ knowledge  mcp/server.py   search_knowledge / list_knowledge  ── usa BGE-M3
                    └─ web        mcp/web_server.py  search_web / fetch_page (DuckDuckGo, sem chave)
```

## Componentes

| Componente | Onde | Papel |
|---|---|---|
| **LM Studio 0.4.x** | app + serviço headless, porta 1234 | serve os modelos com o engine MLX (`mlx-llm-…-metal-nax`, aceleradores neurais do M5); expõe OpenAI API e **Anthropic Messages API** (`/v1/messages`) |
| **Roteador** | `router/router.py`, porta 4000 | um único endpoint para o Claude Code; `claude-*` → nuvem (headers repassados, login OAuth intacto), resto → LM Studio. Streaming SSE byte a byte |
| **Executor** | `qwen3.8-27b` + variantes `-low`/`-nothink` | Qwen3.8-27B denso, MLX 4-bit (~16 GB), 119.552 de contexto; classe Sonnet 5 em coding agêntico (SWE-bench Pro 61,7 vs 63,2) |
| **Atendimento** | `gemma-4-26b-a4b-it-qat` | Gemma 4 26B MoE (3,8B ativos), QAT 4-bit (~15 GB), 46 tok/s aquecido, PT-BR |
| **Embeddings** | `text-embedding-bge-m3` | BGE-M3 GGUF (634 MB), dim 1024, 100+ idiomas, retrieval denso+esparso |
| **MCP knowledge** | `mcp/server.py` + `mcp/index.py` | busca vetorial (cosseno, numpy) sobre `knowledge/` e `docs/plans/`; índice SQLite em `knowledge/.index.db` |
| **MCP web** | `mcp/web_server.py` | internet para o modelo local (a WebSearch nativa do Claude Code exige a API da Anthropic) |
| **Scripts** | `bin/` | `serve.sh` (sobe tudo, idempotente), `healthcheck.sh`, `mem-setup.sh`, `claude-local` |
| **LaunchAgents** | `launchd/` | roteador (**instalado**) e healthcheck (opcional) |

## Fluxos

### Desenvolvimento (handoff nuvem → local)

1. Sessão normal (Fable/Opus) planeja com o **Prompt 1** de `docs/plans/PROMPT-HANDOFF.md`
   e salva `docs/plans/<NN>-<slug>.md` no repo-alvo — escopo fechado, restrições verificáveis,
   critério de aceite, bloco "Convenções aplicáveis".
2. Na **mesma janela**, `/model qwen3.8-27b-low` (ou `-nothink`, ou `qwen3.8-27b`) e o
   **Prompt 2**: "Implemente docs/plans/…. Siga à risca. Se algo não funcionar, PARE."
3. Revisão obrigatória do `git diff`; lições → `knowledge/lessons.md`; `python3 mcp/index.py`.
4. `/model claude-fable-5-1` volta para a nuvem na mesma conversa.

Vias alternativas: `bin/claude-local` (terminal, direto no :1234) e
`vscode/executor.code-workspace` (janela dedicada).

### Roteamento e memória

- Só **uma variante do Qwen** cabe junto do Gemma (16 + 15 GB + KV). A troca é feita pelo
  próprio LM Studio: JIT loading + Auto-Evict de modelos JIT (~7 s, pesos em page cache).
  Gemma e BGE são carregados explicitamente pelo `serve.sh` e não são evictados.
- O roteador é **transparente**, com uma exceção decidida pelo usuário (opção C): no caminho
  local remove as tools dos connectors claude.ai (`mcp__claude_ai_*`), que somam ~100K tokens
  e não cabem no contexto do Qwen. Ver `04-decisoes.md`.

### Pipeline de conhecimento (Fable → executor)

- **Camada 1 (determinística)** — `knowledge/conventions/<projeto>.md`, `lessons.md`,
  `adr/`. Entram no `CLAUDE.md` dos repos-alvo e no bloco "Convenções aplicáveis" dos planos.
- **Camada 2 (retrieval)** — MCP `knowledge`, para o que não cabe no contexto.
- **Vedação**: nenhum fine-tuning sobre outputs do Claude (termos da Anthropic). Só retrieval.

## Orçamento de memória (medido)

| Config | Executor | Atendimento | Embeddings | Total |
|---|---|---|---|---|
| **dev (padrão)** | Qwen3.8-27B 4-bit 16,1 GB (JIT, 1 variante) | — | BGE-M3 0,6 GB | **~17 GB + KV** |
| atendimento | idem | Gemma 4 26B-A4B QAT 15,6 GB | BGE-M3 0,6 GB | ~32 GB + KV (apertado) |
| atendimento B | idem | Gemma 4 12B QAT ~7 GB | idem | ~24 GB + KV |

Limite padrão da GPU (~36 GB) bastou para a config A; `bin/mem-setup.sh` eleva a 40 GB para
testar quants de 8 bits. KV cache cresce pouco: Qwen3.8 usa Gated DeltaNet em 48 das 64
camadas (só 16 com KV convencional); Gemma usa sliding window de 1024.

## Números de referência (M5 Pro, medidos)

| Métrica | Valor |
|---|---|
| Qwen decode | ~17 tok/s (teto de banda para denso 27B 4-bit) |
| Qwen prefill | ~1.200 tok/s frio; **cache de prompt**: 31K tokens em 26 s → 1,8 s nos turnos seguintes |
| Gemma decode | 46 tok/s aquecido; 1ª inferência 27 s (compilação Metal → warmup no `serve.sh`) |
| Gemma TTFT com 2 conversas simultâneas | 543 / 727 ms |
| Tarefa trivial via Claude Code (criar arquivo) | 94–127 s (dominado por prefill + raciocínio) |
| Regimes: mesma tarefa CPF+testes | xhigh >238 s sem terminar · `-low` 57 s · `-nothink` 39 s |

Histórico completo em `../evals/results.md`.
