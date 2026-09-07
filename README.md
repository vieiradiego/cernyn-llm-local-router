# cernyn-llm-local-router

Inferência local no MacBook Pro M5 Pro (48 GB) integrada ao Claude Code: **Fable/Opus planejam
na nuvem, um Qwen local executa**, trocando de modelo com `/model` na mesma conversa. Inclui um
modelo de atendimento em PT-BR (Gemma), embeddings (BGE-M3) e dois MCPs (conhecimento e web).

## Quickstart

```sh
# 0. git clone https://github.com/vieiradiego/cernyn-llm-local-router && cd cernyn-llm-local-router && ./install.sh
# 1. LM Studio aberto (ou serviço headless ativo)
bin/serve.sh                      # perfil dev: servidor + BGE-M3; Qwen carrega via JIT no 1º /model
#    bin/serve.sh --atendimento    # perfil atendimento: carrega o Gemma e faz warmup
# 2. Na extensão Claude Code (VS Code), na conversa de sempre:
#    /model qwen3.8-27b-gguf-nothink   ← executor local (padrão; -gguf-low para decisões de arquitetura)
#    /model claude-fable-5-1      ← volta para a nuvem
```

O `install.sh` instala o roteador (`localhost:4000`) como serviço; a extensão passa a apontar para ele
com a setting do VS Code descrita em `docs/02-configuracao.md`. Modelos, variantes de template e
configuração do LM Studio são passos manuais, listados no mesmo documento.
Primeira resposta local leva 1–2 min (prefill); as seguintes usam cache.

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/01-arquitetura.md](docs/01-arquitetura.md) | visão geral, componentes, fluxos, orçamento de memória, números medidos |
| [docs/02-configuracao.md](docs/02-configuracao.md) | LM Studio, modelos e variantes, roteador, VS Code, MCPs, macOS: o que está configurado e como desfazer |
| [docs/03-runbook.md](docs/03-runbook.md) | operação diária, ciclo de uma tarefa, escolha de regime, troubleshooting |
| [docs/04-decisoes.md](docs/04-decisoes.md) | ADRs da stack: por que cada escolha, com evidência; hipóteses refutadas |
| [docs/modelos.md](docs/modelos.md) | matriz de modelos, datas de release, descartes, regra de proveniência |
| [docs/plans/PROMPT-HANDOFF.md](docs/plans/PROMPT-HANDOFF.md) | os dois prompts do fluxo nuvem → local e o que medir |
| [evals/results.md](evals/results.md) | todas as medições (baseline, otimizações, concorrência, web) |
| [docs/historico/plano-fases-0-6.md](docs/historico/plano-fases-0-6.md) | plano original aprovado, com fontes |

## Estrutura

```
bin/          serve.sh (perfis dev/--atendimento) · memguard.sh · healthcheck.sh · mem-setup.sh · claude-local
router/       router.py: roteador Anthropic-API: claude-* → nuvem, resto → LM Studio
mcp/          server.py (knowledge) · index.py (indexador) · web_server.py (web) · .venv
launchd/      router (instalado) · memguard (instalado) · healthcheck (opcional)
knowledge/    conventions/ · lessons.md · adr/: camada determinística + índice vetorial
evals/        coding/ (tarefas reais) · ptbr/ (rubrica + diálogos) · results.md
docs/         arquitetura · configuração · runbook · decisões · modelos · plans/ · historico/
vscode/       executor.code-workspace (via alternativa: janela dedicada)
.mcp.json     MCP knowledge no escopo do projeto
```

## Estado (07/09/2026)

Operacional: roteador transparente (exceção: opção C, remove tools dos connectors claude.ai
no caminho local), três regimes de raciocínio do Qwen escolhíveis pelo `/model`, executor em
llama.cpp (GGUF) para sessões longas, MCP `web` validado, Gemma respondendo em PT-BR a 46 tok/s.
**Evals de código feitas** (9 runs válidos, 0 intervenções): 5 de 7 replays com gabarito
entregaram; o card vivo não entregou em nenhum regime; ver `evals/results.md` e D14 em
`docs/04-decisoes.md`. **Pendente**: diálogos de atendimento (`evals/ptbr/dialogos/`) para o
Gemma; fase 7 (bot) adiada.
