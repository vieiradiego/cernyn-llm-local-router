# Matriz de modelos

Verificado contra as orgs oficiais no Hugging Face em **31/08/2026**.
Reavaliar o executor a cada ~3 meses (próxima revisão: **dez/2026**) — o ritmo do
ecossistema é a razão desta tabela guardar datas.

## Stack ativa (config A — ~33 GB)

| Papel | Modelo | Quant | GB | Contexto | Licença | Release |
|---|---|---|---|---|---|---|
| Executor de código | `mlx-community/Qwen3.8-27B-4bit` | MLX 4-bit | ~17 | 262K nativo (1M YaRN) | Apache 2.0 | 14/08/2026 |
| Atendimento PT-BR | `google/gemma-4-26B-A4B-it` (MoE 25,2B/3,8B ativos) | MLX 4-bit | ~15 | 256K | Apache 2.0 | 02/07/2026 |
| Embeddings / RAG | `BAAI/bge-m3` (denso + esparso) | — | ~1,2 | 8K | MIT | 2024 |

## Variantes de template do executor (mesmo peso, `~/.lmstudio/models/local-llm/`)

| Identificador | Template | Uso |
|---|---|---|
| `qwen3.8-27b-low` | `reasoning_effort` default `low` | executar planos com raciocínio breve (57s vs >238s na tarefa-teste) |
| `qwen3.8-27b-nothink` | `enable_thinking = false` | edições triviais (39s) |
| `qwen3.8-27b` | original (xhigh) | padrão dos scripts; raciocínio máximo (lento) |

## Fallbacks e variantes

| Papel | Modelo | Quant | GB | Quando usar |
|---|---|---|---|---|
| Atendimento (config B) | `google/gemma-4-12B-it-qat-w4a16-ct` (QAT oficial) | int4 QAT | ~7 | Pressão de memória na config A |
| Executor (velocidade) | `mlx-community/Qwen3.8-27B-MTP-4bit` | MLX 4-bit | ~17 | Se o runtime suportar MTP — decodificação especulativa embutida |
| Executor (qualidade) | `mlx-community/Qwen3.8-27B-8bit` | MLX 8-bit | ~29 | Só na config B; medir se compensa a velocidade perdida |
| Embeddings (alternativa) | `Qwen/Qwen3-Embedding-0.6B` | — | ~1,5 | Se precisar de dimensionalidade configurável |

## Plano B do executor (testar só se o Qwen3.8-27B reprovar nas evals)

| Modelo | Arq. | GB (Q4) | Nota |
|---|---|---|---|
| `Qwen/Qwen3-Coder-Next` | 80B-A3B MoE, 262K | ~48,5 (exige IQ4_XS/3-bit) | 71,3% SWE-bench Verified com OpenHands; monopoliza a máquina |
| `mistralai/Devstral-Small-2-24B-Instruct-2512` | 24B denso, 256K | ~15 | dez/2025 — segunda opinião |
| `zai-org/GLM-4.7-Flash` | 31B-A3B MoE | ~18 | jan/2026 — forte em τ²-bench, bilíngue zh-en |

## Descartados (com motivo, para não reavaliar à toa)

| Modelo | Motivo |
|---|---|
| Qwen3.6-27B | Substituído pelo 3.8 (SWE-bench Pro 53,5% → 61,7%) |
| Qwen3.8-Flash-Next | 125B-A6B, ~62 GB em 4-bit; licença Qwen Community (não Apache) |
| GLM-5.3-Flash | 321B — não cabe em 48 GB |
| SABIÁ (Maritaca) | Sabiá-3/4 API-only; Sabiá-7B com licença LLaMA-1, só pesquisa — **veta uso comercial** |
| Tucano 2 (0,5-3,7B) | Pequeno demais para atendimento; útil como triagem e fonte da rubrica de eval PT-BR |
| Falcon H1R 7B | Modelo de raciocínio, não agêntico |

## Regra de proveniência

Baixar quants **somente** de: `mlx-community`, `unsloth`, `ggml-org` ou da org oficial do
modelo. A busca por "Qwen3.8-27B" no HF retorna dezenas de finetunes de terceiros
(abliterated / uncensored / MAX-NEO) com nomes quase idênticos aos oficiais.

## Benchmarks de referência (vendor-reported — as evals locais é que decidem)

| Benchmark | Qwen3.8-27B | Qwen3.6-27B | Qwen3-Coder-Next |
|---|---|---|---|
| SWE-bench Pro | **61,7%** | 53,5% | 44,3% |
| Terminal Bench 2.1 | **73,0%** | 63,4% | — |
| OSWorld-Verified | **84,3%** | 63,9% | — |
| SWE-bench Verified (OpenHands) | — | — | 71,3% |

| Benchmark | Gemma 4 26B-A4B | Gemma 4 12B |
|---|---|---|
| MMLU Pro | **82,6%** | 77,2% |
| MMMLU (multilíngue) | — | 83,4% |

## Adiado: autocomplete local (FIM)

Tab-completion no VS Code (Continue/Cline) exigiria um modelo FIM ~3B sempre quente
disputando GPU com os ~30 GB residentes — e a GPU já opera no teto de banda durante o
executor. Reavaliar após as evals; candidato: um Qwen coder ~3B.
