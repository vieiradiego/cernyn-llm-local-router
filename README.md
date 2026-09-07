# LLM Local para o seu Negócio
### Roteador Cernyn: um modelo local dentro do Claude Code, no seu Mac, com o contexto da sua empresa.

> Uma IA que roda na sua máquina, aprende o contexto do seu negócio e executa tarefas reais. **Modelo local e Claude na mesma conversa do VS Code, trocando com `/model`. Sem enviar dados para fora, sem perder o login nem os connectors.**

> Engenharia biônica aplicada ao dia a dia de quem constrói software. Testado com tarefas reais: 5 de 7 entregues sem intervenção humana.

[![Artigo](https://img.shields.io/badge/Artigo-como_rodar_um_LLM_local-22D3EE.svg?style=for-the-badge)](https://cernyn.com/insights/llm-local-executor-negocio)
[![by Cernyn](https://img.shields.io/badge/by-Cernyn-22D3EE.svg?style=flat-square)](https://cernyn.com/)
[![Padrão Cernyn](https://img.shields.io/badge/padr%C3%A3o-cernyn--patterns--claude-8B5CF6.svg?style=flat-square)](https://github.com/vieiradiego/cernyn-patterns-claude)
[![macOS Apple Silicon](https://img.shields.io/badge/macOS-Apple_Silicon-000000.svg?style=flat-square)](#pré-requisitos)
[![LM Studio 0.4+](https://img.shields.io/badge/LM_Studio-0.4%2B-8B5CF6.svg?style=flat-square)](https://lmstudio.ai/)
[![PT-BR](https://img.shields.io/badge/idioma-PT--BR-009C3B.svg?style=flat-square)](#)
[![Status: Ativo](https://img.shields.io/badge/status-ativo-22D3EE.svg?style=flat-square)](#)
[![CI](https://github.com/vieiradiego/cernyn-llm-local-router/actions/workflows/ci.yml/badge.svg)](https://github.com/vieiradiego/cernyn-llm-local-router/actions)

## Para quem é

Líderes técnicos e executivos que querem **provar o valor de um LLM local** antes de comprometer orçamento com nuvem ou com fine-tuning: código sensível que não pode sair da máquina, atendimento em português com documentos internos, ou simplesmente a curiosidade de saber o que um Mac de 48 GB entrega hoje. O repositório foi desenhado para ser **clonado, configurado e medido em uma sessão**, com cada decisão explicada e cada número reproduzível.

Leia primeiro o artigo: [Como rodar um LLM local que executa tarefas reais do seu negócio](https://cernyn.com/insights/llm-local-executor-negocio). Este README é o passo a passo que o artigo resume.

## O que você ganha

| Peça | O que faz | Por que importa |
|---|---|---|
| **Roteador** (`router/`) | Decide por nome de modelo: `claude-*` vai para a Anthropic com as suas credenciais, o resto vai para o LM Studio | Modelo local e Claude na **mesma conversa** do Claude Code. Transparente: não altera parâmetros nem troca modelo por baixo dos panos |
| **Variantes de template** (`bin/gguf-variant.sh`) | Três regimes de raciocínio do mesmo modelo: sem raciocínio, breve, máximo | O LM Studio ignora os parâmetros da API que controlariam isso. Você escolhe o regime no `/model` |
| **Perfis de memória** (`bin/serve.sh`, `bin/memguard.sh`) | Um perfil por tipo de trabalho e um guarda que descarrega o modelo antes do sistema travar | Foi o que impediu o segundo travamento a 72 GB numa máquina de 48 |
| **Conhecimento do negócio** (`knowledge/`, `mcp/`) | Convenções e decisões dentro do plano de cada tarefa, mais um MCP de busca sobre a sua documentação e um MCP de internet | Adapta o modelo ao seu contexto **sem treinar nada** |
| **Avaliação com tarefas reais** (`evals/`) | Replay de cards já entregues, com testes de referência escondidos, medindo tempo, turnos e memória | Decide com evidência se o modelo entra no dia a dia |

## Pré-requisitos

Instalação única, cerca de 30 minutos, a maior parte em download de modelos.

- **Mac com Apple Silicon e 48 GB de memória unificada.** Com 32 GB, use só o executor de código (sem o modelo de atendimento) e recalcule os limites do guarda de memória em `templates/com.local-llm.memguard.plist.tpl`.
- [**LM Studio 0.4+**](https://lmstudio.ai/) aberto pelo menos uma vez, com o CLI ativado: `~/.lmstudio/bin/lms bootstrap`.
- [**Claude Code**](https://claude.com/claude-code) com login ativo: CLI ou extensão do VS Code.
- **Python 3.10+** e **Git**.

## Rode em 5 passos

### 1. Baixe os modelos (uma vez)

```bash
export PATH="$HOME/.lmstudio/bin:$PATH"
lms get unsloth/qwen3.8-27b                     # executor de código: escolha o quant UD-Q4_K_S (~16 GB)
lms get gpustack/bge-m3-GGUF                     # embeddings para o MCP de conhecimento (~0,6 GB)
lms get mlx-community/gemma-4-26B-A4B-it-qat-4bit   # opcional: atendimento em português (~15 GB)
```

Baixe quants só de `unsloth`, `mlx-community`, `ggml-org`, `lmstudio-community` ou da organização oficial do modelo. A busca no Hugging Face está cheia de variantes de terceiros com nomes quase idênticos.

### 2. Ajuste o LM Studio

Em **Settings → Developer**: ative *Enable Local LLM Service* (a API responde sem a janela aberta), ative o carregamento sob demanda com descarte do modelo anterior (*Auto-Evict*) e deixe o guardrail de memória em **Strict**. O servidor fica em `localhost:1234` e nunca em `0.0.0.0`: não há autenticação.

### 3. Clone e instale

```bash
git clone https://github.com/vieiradiego/cernyn-llm-local-router.git
cd cernyn-llm-local-router
./install.sh --dry-run   # mostra o que vai fazer
./install.sh             # roteador e guarda de memória como serviços, MCPs no Claude Code
```

O instalador gera os arquivos de serviço a partir de `templates/`, cria o ambiente Python dos MCPs, registra os MCPs `knowledge` e `web` no Claude Code e instala dois LaunchAgents: o roteador na porta 4000 e o guarda de memória. `./uninstall.sh` desfaz tudo.

### 4. Crie as variantes de raciocínio

```bash
GGUF=$(ls ~/.lmstudio/models/unsloth/qwen3.8-27b/*.gguf | head -1)
for m in nothink low base; do
  bin/gguf-variant.sh "$GGUF" $m ~/.lmstudio/models/local-llm/Qwen3.8-27B-GGUF-$m
done
lms ls   # anote os nomes que aparecem: são eles que você digita no /model
```

Cada variante ocupa cerca de 16 GB em disco e aparece como um modelo separado. O script também corrige o template para aceitar a mensagem `system` que o Claude Code envia depois do turno do usuário e que o llama.cpp rejeitaria.

### 5. Aponte o VS Code e troque de modelo

Na extensão Claude Code, em *Settings → Environment Variables*, adicione `ANTHROPIC_BASE_URL` = `http://localhost:4000` e recarregue a janela. Na conversa de sempre:

```
/model qwen3.8-27b-gguf-nothink    # executor local, padrão (o nome exato vem do lms ls)
/model qwen3.8-27b-gguf-low        # raciocínio breve, para decisões de arquitetura
/model claude-fable-5-1            # volta para a nuvem
```

A primeira resposta local leva de 1 a 2 minutos (carga do modelo e prefill). As seguintes usam cache. Para subir a stack no dia a dia: `bin/serve.sh` (perfil dev) ou `bin/serve.sh --atendimento` (carrega o Gemma).

## Como adaptar ao seu negócio

### Dê contexto ao modelo, não treino
Escreva as convenções do projeto em `knowledge/conventions/<projeto>.md`, as decisões de arquitetura em `knowledge/adr/` e as lições de cada tarefa em `knowledge/lessons.md`. O plano de cada tarefa abre com um bloco "Convenções aplicáveis" copiado de lá: o modelo local segue melhor o que está dentro do plano do que o que precisa buscar. Depois, indexe: `mcp/.venv/bin/python mcp/index.py`. O MCP `knowledge` passa a responder `search_knowledge` no Claude Code, com embeddings gerados pelo próprio LM Studio.

### Faça o Claude planejar e o modelo local executar
O fluxo que medimos: Claude Fable ou Opus escreve o plano em `docs/plans/<tarefa>.md` (modelo em `docs/plans/README.md`), você troca para o modelo local com `/model` e pede "implemente o plano". O plano precisa trazer o **como**: versão da biblioteca, flag do instalador, trecho de configuração. O modelo local não erra lógica; erra o que não sabe do projeto.

### Meça com as suas tarefas
Copie `evals/coding/tarefas/EXEMPLO.md` e `EXEMPLO.env` para um card já entregue do seu projeto, aponte `BASE_SHA` para o commit anterior e `REF_SHA` para o commit real, e rode:

```bash
ENGINE=gguf evals/run.sh <TAREFA> nothink 60 90    # 60 turnos, 90 minutos
```

O harness cria uma worktree descartável fora do seu repositório, executa o plano com `claude -p` sem ninguém no loop, roda lint, typecheck, build e os testes de referência escondidos, e grava tempo, turnos e memória em `evals/results/`. O seu repositório não ganha branch, commit nem pasta.

## Números medidos

MacBook Pro M5 Pro 48 GB, setembro de 2026, modelo em 4 bits no engine llama.cpp. Cada linha é uma execução única; leia como evidência, não como benchmark.

| Tarefa real | Sem raciocínio | Raciocínio breve | Máximo |
|---|---|---|---|
| Débito de UI + JSON-LD | 15,5 min, 54/54 testes | 36 min, 54/54 | 55 min, 54/54 |
| Bug P1 em 7 arquivos | build quebrou | 68 min, 41/41 e2e | não rodado |
| Feature: tema claro e CSP | 23 min, 60/60 | timeout 90 min | não rodado |
| Card vivo: lint a11y + hooks | incompleto (cap 60 turnos) | incompleto (cap 60 turnos) | não rodado |

Outros números que moldaram a stack: 152 tools por requisição com cinco connectors ligados (534 KB → 154 KB depois do corte no caminho local); raciocínio máximo sem terminar em 4 min contra 57 s breve e 39 s sem; MLX com pico de 37 GB num prompt de 90 mil tokens contra 26 GB estáveis no llama.cpp. Todos em [`evals/results.md`](evals/results.md).

## Documentação

- [`docs/01-arquitetura.md`](docs/01-arquitetura.md): componentes, fluxo de uma requisição, orçamento de memória.
- [`docs/02-configuracao.md`](docs/02-configuracao.md): cada ajuste do LM Studio, variáveis do roteador, MCPs, como desfazer.
- [`docs/03-runbook.md`](docs/03-runbook.md): operação diária, troubleshooting por sintoma.
- [`docs/04-decisoes.md`](docs/04-decisoes.md): as decisões D01 a D14 com evidência, e as hipóteses testadas e refutadas.
- [`docs/modelos.md`](docs/modelos.md): por que estes modelos e não outros.
- [`evals/coding/README.md`](evals/coding/README.md): o harness de avaliação em detalhe.
- [`README.en.md`](README.en.md): versão em inglês, em formato de artigo.

## Para o time de dev quando virar produto

- Roteador de 170 linhas em Python padrão, sem dependências, com smoke test contra upstreams falsos (`tests/smoke.sh`) e CI no GitHub Actions.
- Credenciais do Claude nunca vão para o destino local; o roteador escuta só em `localhost`.
- MCP de internet com proteção contra SSRF (só http/https, sem rede privada, redirects revalidados, corpo limitado).
- Scripts em POSIX sh, LaunchAgents gerados de templates, `uninstall.sh` que reverte a instalação.
- Nada aqui treina modelo sobre saídas do Claude: o pipeline de conhecimento é só retrieval, dentro dos termos de uso.

## Limitações assumidas

- **Não é produto.** É a stack de uma máquina, documentada para ser reproduzida e medida.
- **macOS e Apple Silicon.** Os scripts usam `footprint`, `memory_pressure` e clone APFS; Linux exige adaptação.
- **Os limites de memória são de 48 GB.** Com outra configuração, recalcule o guarda e o contexto máximo.
- **Uma execução por célula.** Os números orientam a decisão, não substituem a sua avaliação com as suas tarefas.
- **O roteador encaminha as suas próprias credenciais** do Claude Code para a Anthropic. Nunca o exponha fora da máquina nem use esses tokens fora do Claude Code.

## Quer apoio especializado?

Se este catalisador te animou e você quer ir mais fundo, colocar um modelo local no fluxo do seu time, adaptar ao seu negócio ou validar uma ideia maior, a **Cernyn** combina engenheiros sêniores com IA agêntica integrada ao processo. Fale com a gente: [pinus@cernyn.com](mailto:pinus@cernyn.com).

---

**Cernyn** · Consultoria Biônica de Engenharia Digital · [cernyn.com](https://cernyn.com/)
