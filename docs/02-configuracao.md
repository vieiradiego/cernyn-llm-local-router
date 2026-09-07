# 02 — Configuração

Tudo que foi configurado nesta máquina, onde vive e como desfazer.

## Instalação reproduzível (`install.sh`)

`./install.sh [--dry-run]` gera `launchd/*.plist` e `.mcp.json` a partir de `templates/`
(substituindo `__REPO__`/`__HOME__`), cria a venv dos MCPs, registra `knowledge` e `web` no
escopo do usuário do Claude Code e instala os LaunchAgents do roteador e do guarda de memória.
`./uninstall.sh` desfaz o que está fora do repositório. Os arquivos gerados são ignorados pelo
git. Teste do roteador sem LM Studio nem Anthropic: `tests/smoke.sh` (servidores falsos em
portas 44xx; verifica roteamento por nome, opção C só no caminho local, streaming SSE).

## LM Studio (0.4.23, instalado via `brew install --cask lm-studio`)

CLI `lms` em `~/.lmstudio/bin` (após `lms bootstrap`). Modelos em `~/.lmstudio/models/`.

| Item | Valor | Onde / como |
|---|---|---|
| Servidor local | `localhost:1234` — **nunca `0.0.0.0`** (sem autenticação) | Developer → Server |
| Serviço headless | `enableLocalService: true` | Settings → Developer → *Enable Local LLM Service* |
| Auto-Evict de modelos JIT | `developer.unloadPreviousJITModelOnLoad: true` | troca de variante do Qwen pelo `/model` |
| TTL de modelos JIT | `developer.jitModelTTL: 3600 s` | Qwen ocioso descarrega em 1 h |
| Guardrail de carregamento | `modelLoadingGuardrails.mode: high` | capa o contexto do Qwen em 119.552 (modelo suporta 262K). **Não impediu** o incidente D12 (2 Qwen + Gemma via JIT+explícito) — considerar *Strict* |
| Contexto padrão | `defaultContextLength: 8192` | **não** se aplica a cargas pela API (medido: 119.552) |
| Parallel requests | 4 | 3 req concorrentes de 31K: 9–22 s vs 77 s cada com 1 |
| Formato / engine | MLX (`mlx-llm-mac-arm64-apple-metal-nax-advsimd@1.11.0`) | Qwen e Gemma; BGE-M3 em GGUF/llama.cpp |

Fatos operacionais: `lms` **trava** ("Waking up LM Studio service…") se o app não estiver
aberto e o serviço headless não estiver ativo; `lms load` **não é idempotente** (carrega uma 2ª
instância `modelo:2`) — o `serve.sh` confere antes.

### Modelos instalados

| Identificador (`lms ps`) | Origem | Notas |
|---|---|---|
| `qwen3.8-27b` | `mlx-community/Qwen3.8-27B-4bit` | template original: thinking `xhigh` |
| `qwen3.8-27b-low` | `~/.lmstudio/models/local-llm/Qwen3.8-27B-4bit-low` | symlinks para o peso acima + `chat_template.jinja` com `reasoning_effort` default `low` |
| `qwen3.8-27b-nothink` | `~/.lmstudio/models/local-llm/Qwen3.8-27B-4bit-nothink` | idem, com `{%- set enable_thinking = false %}` no topo |
| `gemma-4-26b-a4b-it-qat` | `mlx-community/gemma-4-26B-A4B-it-qat-4bit` | QAT oficial em MLX |
| `text-embedding-bge-m3` | `gpustack/bge-m3-GGUF` | embeddings |
| `qwen3.8-27b-gguf` (+ `-low`, `-nothink`) | `unsloth/qwen3.8-27b` (UD-Q4_K_S) + variantes em `local-llm/Qwen3.8-27B-GGUF-*` | executor para sessões longas — engine llama.cpp, carregar com `-c 131072 --parallel 1` (ver D13) |

Por que variantes por template: o LM Studio **ignora** os parâmetros da API que controlariam o
thinking do Qwen (`thinking.type=disabled`, `chat_template_kwargs.enable_thinking`,
`reasoning_effort`, `/no_think` — todos testados). Regenerar uma variante: criar diretório em
`~/.lmstudio/models/local-llm/`, symlinkar todos os arquivos do original exceto
`chat_template.jinja`, e copiar o template editado.

Regra de proveniência: baixar quants só de `mlx-community`, `unsloth`, `ggml-org`,
`lmstudio-community` ou da org oficial — a busca no HF está cheia de finetunes de terceiros
com nomes quase idênticos.

### Perfis de memória (`bin/serve.sh`, pós-incidente D12)

| Perfil | Residentes explícitos | Qwen | Orçamento típico |
|---|---|---|---|
| **dev** (padrão) | BGE-M3 (0,6 GB) | só via JIT — uma variante por vez, trocada pelo `/model` | 16 GB + KV (≤10 GB com 4 slots × 40K) ≈ 27 GB |
| `--atendimento` | BGE-M3 + Gemma (15,6 GB) | idem | ≈ 43 GB — sem folga para sessões longas de dev |

Regra: **nunca** `lms load` manual de uma variante do Qwen — vira "explícita" e o Auto-Evict
deixa de trocá-la, somando 16 GB a cada variante escolhida no `/model`.

### Prompt cache store do engine MLX (medido 06/09/2026)

O engine (`~/.lmstudio/.internal/utils/node`) guarda em **memória de GPU** um "prompt cache
store" com os prefixos já processados (é o que dá 1,8 s de prefill no 2º turno). Cresce ~3,5 GB
a cada ~120 registros (3 prompts de 31K) e o teto configurado é 163 GB — na prática, sem
teto. Footprint medido do engine com **um** Qwen: 21 GB em regime, **pico 31 GB**. Não há
flag no `lms load` nem chave de config para limitá-lo (as chaves de KV quantization são só
do llama.cpp). Mitigação: `bin/memguard.sh` (LaunchAgent `com.local-llm.memguard`, 30 s):
livre < 15 % ou engine > 34 GB → descarrega o Qwen (JIT recarrega em ~7 s, cache limpo);
livre < 8 % → descarrega tudo. Log `/tmp/local-llm-memguard.log`. Ajustes via
`MEMGUARD_MIN_FREE_PCT`, `MEMGUARD_CRIT_FREE_PCT`, `MEMGUARD_MAX_ENGINE_GB` no plist.

Guardrail do LM Studio: a escala é Off < **Low** < Medium < High < Strict. *Low* é o mais
permissivo. Recomendado: **Strict** (age só no load; não impede o crescimento do cache).

## Roteador (`router/router.py`)

LaunchAgent `~/Library/LaunchAgents/com.local-llm.router.plist` (fonte em `launchd/`):
`/usr/bin/python3 router/router.py 4000`, `RunAtLoad` + `KeepAlive`, log em
`/tmp/local-llm-router.log`.

| Variável (no plist) | Valor atual | Efeito |
|---|---|---|
| `ROUTER_SANITIZE_LOCAL` | **1** (opção C) | no caminho local, remove tools `mcp__claude_ai_*` |
| `ROUTER_LOCAL_STRIP_TOOLS` | `mcp__claude_ai_` (padrão) | prefixos removidos quando sanitize=1 |
| `ROUTER_LOCAL_MAX_TOKENS` | 0 (padrão) | sem cap de `max_tokens` |
| `ROUTER_AUTO_SWAP` | 0 (padrão) | troca de variante fica com o LM Studio (JIT) |
| `ROUTER_ALIASES` | vazio (padrão) | nomes = identificadores do LM Studio |
| `ROUTER_DUMP` | — | debug: salva corpos das requisições locais num diretório |

Comandos: recarregar `launchctl kickstart -k gui/$(id -u)/com.local-llm.router`; remover
`launchctl bootout gui/$(id -u)/com.local-llm.router && rm ~/Library/LaunchAgents/com.local-llm.router.plist`.
**Se o roteador cair, toda sessão da extensão falha (nuvem inclusive)** — por isso KeepAlive e
vigilância em `serve.sh`/`healthcheck.sh`.

## VS Code / Claude Code

**User settings** (`~/Library/Application Support/Code/User/settings.json`, backup
`settings.json.bak-20260906-*`):

```json
"claudeCode.environmentVariables": [
  { "name": "ANTHROPIC_BASE_URL", "value": "http://localhost:4000" }
]
```

Só isso. Sem API key (o login claude.ai continua valendo — testado: connectors seguem ativos
na nuvem), sem `DEFAULT_*_MODEL`. Requer **Developer: Reload Window** após mudar. Na conversa:
`/model qwen3.8-27b-low` ↔ `/model claude-fable-5-1`.

**MCPs no escopo do usuário** (`claude mcp list`):

| Nome | Comando | Tools |
|---|---|---|
| `knowledge` | `mcp/.venv/bin/python mcp/server.py` | `search_knowledge`, `list_knowledge` |
| `web` | `mcp/.venv/bin/python mcp/web_server.py` | `search_web`, `fetch_page` |

Também há `.mcp.json` no repo (escopo de projeto) com o `knowledge`. Remover:
`claude mcp remove -s user <nome>`.

**Vias alternativas** (não dependem do roteador):
- `bin/claude-local` — aponta direto para :1234 com `ANTHROPIC_MODEL` (obrigatório: o modelo
  fixado no settings global sobrepõe os `DEFAULT_*`) e `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`.
- `vscode/executor.code-workspace` — mesmas variáveis em escopo de workspace; adicione os
  repos-alvo em `folders`.

## Ambiente Python dos MCPs

`mcp/.venv` (Python 3.14) com `mcp>=2` (SDK 2.x: `MCPServer`, não `FastMCP`), `numpy`,
`ddgs`, `trafilatura`, `httpx`. Recriar: `python3 -m venv mcp/.venv && mcp/.venv/bin/pip
install -r mcp/requirements.txt`. Logs das libs vão para stderr (stdout é o protocolo MCP).

## macOS

- `iogpu.wired_limit_mb`: padrão (0 → ~36 GB) bastou; `sudo bin/mem-setup.sh` sobe para
  40 GB, **não persiste** entre reboots (intencional: evita boot loop).
- Energia: na tomada, Low Power Mode off; chip Pro perde 20–40 % após 10–15 min sustentados.
- `launchd/com.local-llm.healthcheck.plist`: sonda a cada 60 s; **não instalado** (decisão do
  usuário) — instruções no próprio arquivo.
