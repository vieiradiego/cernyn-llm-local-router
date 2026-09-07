# Resultados das evals

## Baseline do setup (01/09/2026, máquina fria, GPU no limite padrão ~36 GB)

Stack residente: qwen3.8-27b (14,98 GiB) + gemma-4-26b-a4b-it-qat (14,57 GiB) +
text-embedding-bge-m3 (605 MiB) ≈ 30 GB — coexistem sem pressão de memória.

| Medição | Valor | Nota |
|---|---|---|
| Qwen3.8 decode (contexto curto) | ~17 tok/s | teto de banda p/ denso 27B 4-bit (307 GB/s ÷ ~15,5 GB ≈ 20); artigos citando 40+ eram MoE |
| Qwen3.8 thinking mode | ON por padrão | 1ª resposta gastou os 200 tokens em `reasoning_content`; orçar max_tokens ≥ 800 ou desativar thinking |
| Gemma 1ª inferência (fria) | 27 s / ~5 tok/s | compilação Metal — warmup obrigatório no serve.sh antes de expor a clientes |
| Gemma aquecido | **46 tok/s**, resposta 150 tok em 3,1 s | dentro do alvo da rubrica (<8 s) |
| Gemma TTFT, 2 conversas simultâneas | 543 ms / 727 ms | alvo <3 s ✓ (parallel requests OK) |
| Gemma PT-BR (1 amostra) | sem deriva PT-PT | "Sinto muito pelo transtorno… te ajudar" — registro correto |
| BGE-M3 embeddings | dim 1024, OK | via /v1/embeddings |
| /v1/messages (Anthropic API) | HTTP 200 | Claude Code fala direto com o LM Studio |
| E2E claude-local (tarefa trivial: criar hello.py) | **sucesso, 122 s, 0 intervenções** | prefill do system prompt domina o tempo no denso 27B |
| Escuta de rede | 127.0.0.1:1234 apenas | verificação 12 ✓ |

Pendências: tok/s @64K, medição pós-15 min (throttling) e teste de contenção (verif. 10)
dependem das tarefas reais de evals/coding/; `sudo bin/mem-setup.sh` ainda não rodado
(config atual coube no limite padrão).

## Otimizações medidas (06/09/2026, Qwen3.8-27B 4-bit, M5 Pro)

| Experimento | Resultado | Decisão |
|---|---|---|
| E1 idioma PT vs EN (entrada) | 96 vs 87 tokens (+10% PT) | marginal; planos em PT, código em EN |
| E1 idioma (raciocínio) | 11,1K vs 11,5K chars — igual | modelo pensa em inglês sempre |
| E2 thinking xhigh (padrão) | 3.500 tok / >238s **sem resposta** | inaceitável como padrão |
| E2 variante `-low` | 965 tok / 57s, resposta completa | **novo padrão do executor** |
| E2 variante `-nothink` | 673 tok / 39s, resposta completa | edições triviais |
| E2 desligar via API (`thinking.type=disabled`, `chat_template_kwargs`, `reasoning_effort`, `/no_think`) | nenhum funciona no LM Studio | controle só via template |
| E3 cache de prompt (31K tokens, 2 envios) | 26,3s → 1,8s (cache_read 31.232) | prefill não é gargalo |
| Tools connectors removidas (router) | payload 512 KB → 131 KB (~32K tok) | manter |
| Claude Code -p trivial via router | 219s → 94s (betas ON) | — |
| Re-teste (roteador TRANSPARENTE, `-low` via JIT nativo, payload intacto 31K tok, betas ON) | **ok em 127s**; 1º envio 500 durante o swap JIT, retry automático 200 | roteador fica transparente |
| Mesmo re-teste com `qwen3.8-27b` (xhigh) | >9 min sem resposta (3 reenvios) — comportamento do modelo, não do roteador | escolha informada do usuário |
| Header `anthropic-beta` direto no LM Studio | 200 | remoção era desnecessária |
| JIT via API: contexto do modelo carregado | 119.552 (não os 8192 do `defaultContextLength`) | troca nativa funciona |
| Concorrência: 3 req de 31K, PARALLEL=4 | 200/200/200 em 9s/22s/22s | hipótese "slots dividem contexto" refutada; manter 4 |
| Concorrência: 3 req de 31K, PARALLEL=1 | 200/200/200 em 77s cada (serializa) | pior |
| Sequência grande→minúscula→grande (+cache_control) | tudo 200 | 500 intermitente não reproduzido |
| WebFetch built-in com Qwen | funciona (128s, com 500/400 e retries no meio) | ok mas lento |
| WebSearch built-in com Qwen | **não funciona** (depende da API Anthropic) | → MCP `web` |
| MCP `web` search_web via Qwen/roteador | 2 resultados reais em 91s | adotado (escopo usuário) |

| **Sessão agêntica real (replay LUM-114, MLX, 1 Qwen, parallel 4 e 1)** | engine oscila 16→37 GB por requisição; memguard descarregou 11× em 50 min; executor nunca completou um turno | MLX inviável para sessões longas em 48 GB |
| Prompt único ~90K tokens — MLX `-low` | prefill 311 s (~284 tok/s); **pico 37 GB**, 29 GB em repouso depois; livre mín. 10% | pico transitório do prefill + retenção |
| Prompt único ~90K tokens — GGUF UD-Q4_K_S / llama.cpp (c=131072, parallel 1) | prefill 634 s (~141 tok/s); RSS ~26 GB, sem pico; livre mín. 33% | memória previsível, 2× mais lento no prefill longo |

| Claude Code → llama.cpp (GGUF original) | **500** "System message must be at the beginning": o Claude Code envia uma mensagem `role: system` depois da do usuário; o template do Qwen3.8 faz `raise_exception`, o minja executa (o renderizador do MLX tolera) | variantes GGUF com o raise trocado por render de bloco system (`bin/gguf-variant.sh`) — payload real 200 |
| GGUF `-low` no llama.cpp (sanidade CPF) | 1.500 tok em 72 s (~21 tok/s, MTP speculativo ativo) com texto | ok |

## Replays com gabarito (projeto Next.js 16 real, privado) — resultados válidos

| Tarefa | Regime / engine | Turnos | Tempo | check | build | e2e de referência | Proibidos | Intervenções |
|---|---|---|---|---|---|---|---|---|
| LUM-114 (débito UI + JSON-LD) | `-low` / llama.cpp GGUF | 46 | 36 min | ✓ | ✓ | **54 passed, 0 failed** (baseline: 5 failed) | nenhum | 0 (autônomo) |
| LUM-114 (débito UI + JSON-LD) | `-nothink` / llama.cpp GGUF | 44 | **15 min 31 s** | ✓ | ✓ | **54 passed, 0 failed** | nenhum | 0 (autônomo); 40 req / 0 erros; relatório final completo |
| LUM-114 (débito UI + JSON-LD) | base (xhigh) / llama.cpp GGUF | 57 | 55 min 24 s | ✓ | ✓ | **54 passed, 0 failed** | nenhum | 0 (autônomo); 51 req / 0 erros |
| LUM-103 (estados de erro, bug P1) | `-nothink` / llama.cpp GGUF | 61 (cap) | 28 min 22 s | ✓ | **✗** | não rodou (sem `out/`); **unit de referência 19/19 ✓** | nenhum | 0; estourou o cap de 60 turnos. Falha: um hook client chamado dentro de um server component → prerender quebra. Lib correta; fronteira client/server errada |
| LUM-103 (estados de erro, bug P1) | `-low` / llama.cpp GGUF | 61 (cap) | 68 min 15 s | ✓ | ✓ | **e2e 41 passed, 0 failed**; unit 19/19 ✓ | nenhum | 0; 62 req / 0 erros. Criou um componente `"use client"` separado para o aviso (a fronteira que o nothink errou); cap cortou só a mensagem final |

Notas: o modelo foi descarregado pelo memguard no último turno (livre 17 %, engine 16 GB — o
resto era Chrome/VS Code), depois de a implementação estar completa; diff 5 arquivos, +143/−7,
primitivo de rolagem horizontal conforme o contrato do plano. Detalhes: `results/LUM-114-low/`.

**LUM-114 — A/B completo**: os três regimes entregam o mesmo resultado (aceite 100 %); o custo é tempo: nothink 15,5 min < low 36 min < xhigh 55 min.

| LUM-111 (tema claro + alternador, feature P2) | `-nothink` / llama.cpp GGUF | 53 | 23 min 21 s | ✓ | ✓ | **e2e 60 passed, 0 failed** (tema + layout + hidratação/CSP) | nenhum | 0; 47 req / 0 erros; adicionou teste unitário do tema sem ser pedido (regra 1 do repo) |
| LUM-111 (tema claro + alternador, feature P2) | `-low` / llama.cpp GGUF | ? | **90 min (TIMEOUT)** | ✗ | ✓ | 27 failed / 33 passed (alternador não construído) | nenhum | 0; só 35 req em 90 min (~2,5 min/turno deliberando); 25 leituras antes da 1ª escrita aos 67 min |

**A/B por tarefa** — nenhum regime domina:

| Tarefa | nothink | low | xhigh |
|---|---|---|---|
| LUM-114 (débito UI) | ✓ 15,5 min | ✓ 36 min | ✓ 55 min |
| LUM-103 (bug, fronteira client/server) | ✗ build | ✓ 68 min | — |
| LUM-111 (feature tema + CSP) | ✓ 23 min | ✗ timeout 90 min | — |

Leitura: `nothink` é o padrão (mais rápido, 2/3); `low` resolve onde há decisão de arquitetura
mas pode deliberar demais; `xhigh` não trouxe ganho. Placar de entregas completas: 5 de 7 runs
válidos; 0 intervenções em todos.

| LUM-128 (vivo: a11y lint + hooks) | `-nothink` / llama.cpp GGUF | 61 (cap) | 14 min | ✗ | ✓ | n/a | nenhum | **INVÁLIDO (harness)**: `npm install` bloqueado pela allowlist → o executor repetiu o mesmo comando **32×** até o cap. Config do ESLint estava correta. Confirma o guarda-corpo "detector de não-convergência": o modelo não reconhece a negação e insiste |

| LUM-128 (vivo: a11y lint + hooks) | `-nothink` / llama.cpp GGUF | 61 (cap) | 12,5 min | ✗ (2 erros a11y restantes) | ✓ | n/a (aceite específico ✗) | nenhum | **Válido, incompleto**: instalou as deps (resolveu conflito de peer com `--legacy-peer-deps`), configurou o jsx-a11y corretamente (contornou "Cannot redefine plugin" do eslint-config-next), corrigiu 1 de 3 apontamentos; hooks do Lefthook **não escritos** (só o exemplo gerado pelo `lefthook install`), sem script `prepare`. ~25 dos 61 turnos foram descoberta de tooling (versões, peer deps, API do plugin, internals do eslint-config-next). Sem loops: 16 erros, todos exploratórios |

| LUM-128 (vivo: a11y lint + hooks) | `-low` / llama.cpp GGUF | 61 (cap) | 56 min | ✗ (test: `vite` ausente) | ✓ | n/a (aceite específico ✗) | nenhum | **Válido, incompleto**: config do ESLint mais limpa que a do nothink (só `rules` do recomendado, sem redefinir plugin); lint ✓ e typecheck ✓ com os 3 apontamentos tratados (2 via `eslint-disable` justificado); hooks **não escritos** — ao bater o cap estava lendo o README do lefthook. `npm run test` quebrou porque `npm install --legacy-peer-deps` (resposta ao ERESOLVE do plugin com ESLint 10) **podou o `vite`**, peer do vitest — o nothink cometeu o mesmo erro (lock com ~790 linhas removidas nos dois) |

**Leitura do card vivo**: nenhum regime entregou. Em ambos, ~40 % dos turnos foram descoberta de tooling (versões, peer deps, API do plugin, internals do eslint-config-next, README do lefthook); o cap de 60 turnos, calibrado nos replays, é curto para um card que exige aprender três ferramentas novas. A armadilha comum (`--legacy-peer-deps` removendo peers) é conhecimento que caberia no `knowledge/` — candidata a convenção do projeto.

## Coding (metodologia: evals/coding/README.md)

| modelo | tarefa | concluída | intervenções | violações | escopo abandonado | tok/s @1K | tok/s @64K | tok/s pós-15min | prefill 64K | compactações |
|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | |

## PT-BR (rubrica: evals/ptbr/rubrica.md)

| modelo | diálogo | C1 | C2 | C3 | C4 | C5 | C6 | C7 | média | TTFT | obs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | |

## Latência sob contenção (verificação 10 do plano)

| cenário | TTFT bot | resposta completa | obs |
|---|---|---|---|
| bot sozinho | | | |
| 2 conversas simultâneas | | | |
| durante prefill 64K do executor | | | pior caso — decide coexistência |
