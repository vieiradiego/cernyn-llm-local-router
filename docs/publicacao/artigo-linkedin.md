# Artigo de lançamento (PT-BR e EN) + post curto

> Voz: manual Cernyn (técnica confiante, sem hype, enxuto, sem travessão como conector,
> claims com fonte). Números medidos em 06 e 07/09/2026 num MacBook Pro M5 Pro 48 GB;
> cada célula das tabelas é uma execução única. Detalhes, scripts e logs no repositório.

## PT-BR

**Como rodar um LLM local que executa tarefas reais do seu negócio: o que instalar, o que configurar e as cinco armadilhas que só aparecem com número.**

Rodar um modelo local deixou de ser experimento de fim de semana. Um MacBook de 48 GB roda hoje um modelo de 27 bilhões de parâmetros que entrega código testado, responde clientes em português e fica com todos os dados dentro da máquina. O que falta na maioria dos guias é a segunda metade: como fazer esse modelo trabalhar no seu fluxo, com o seu contexto, e como saber se ele está entregando.

Passei duas semanas montando essa stack e medindo cada decisão. Abaixo está o que eu executaria de novo, na ordem, e o que evitaria. Tudo está num repositório aberto, com os experimentos que deram errado registrados para ninguém repetir.

### 1. Escolha o papel do modelo antes do modelo

A pergunta certa não é "qual é o melhor modelo local", é "que trabalho ele vai fazer". Na minha stack são dois papéis:

- **Executor de código.** Recebe um plano escrito por um modelo de fronteira (Claude Fable ou Opus, na nuvem) e implementa. Aqui entrou o Qwen3.8-27B quantizado em 4 bits.
- **Atendimento em português.** Responde clientes com base em documentos da empresa, com latência de primeiro token abaixo de 1 segundo. Aqui entrou o Gemma 4 26B-A4B, um modelo de especialistas que ativa só 4 bilhões de parâmetros por token.

A divisão importa porque ela define o orçamento de memória. Dois modelos residentes ao mesmo tempo, mais o cache de contexto, foi exatamente o que travou meu Mac com 72 GB alocados numa máquina de 48. A solução foi simples e vale como regra: um perfil por tipo de trabalho, e nunca dois modelos grandes carregados juntos.

### 2. Instale o mínimo: LM Studio, um roteador e uma configuração

**LM Studio** serve os modelos com uma API compatível com OpenAI e Anthropic. Três ajustes que fazem diferença: ativar o serviço local para a API responder sem a janela aberta, ligar o carregamento sob demanda com descarte automático do modelo anterior, e deixar o guardrail de memória em "strict". O guardrail só age na hora de carregar; o que cresce depois é o cache de prompt, e para isso entra o passo 4.

**Um roteador HTTP de 170 linhas** na porta 4000 decide por nome de modelo: pedidos para `claude-*` vão para a Anthropic com as suas credenciais intactas; qualquer outro nome vai para o LM Studio. O ganho é usar o modelo local dentro da mesma conversa do Claude Code no VS Code, trocando com `/model qwen3.8-27b-gguf-nothink` para executar e `/model claude-fable-5-1` para planejar. Sem perder login, assinatura ou connectors. O roteador é transparente por padrão: não altera parâmetros, não troca modelo por baixo dos panos. A única exceção é explícita e está no próximo item.

**Uma configuração no VS Code**: apontar `ANTHROPIC_BASE_URL` para `http://localhost:4000` na extensão do Claude Code. Só isso.

### 3. Corte o que estoura o contexto

Com cinco connectors do claude.ai ligados, o Claude Code mandou 152 definições de tools em toda requisição. 117 delas eram schemas do Notion, Gmail e HubSpot: perto de 100 mil tokens antes da primeira mensagem. Um modelo de 27B com janela de 119 mil tokens não consegue dar um único turno.

O roteador remove só essas tools de connectors no caminho local. O payload cai de 534 KB para 154 KB e o modelo passa a trabalhar. Na nuvem, nada muda. Esse é o tipo de ajuste que precisa ser uma decisão sua, documentada, e não um comportamento escondido.

### 4. Controle o raciocínio pelo template, não pela API

O template do Qwen3.8 liga raciocínio em nível máximo por padrão, e o LM Studio ignora os parâmetros da API que o desligariam. Testei todos, nos dois engines. A saída foi criar variantes do próprio template de chat, com os mesmos pesos: uma sem raciocínio, uma com raciocínio breve, uma com o padrão.

Mesma tarefa: em nível máximo o modelo não terminou de pensar em 4 minutos. Com raciocínio breve, 57 segundos. Sem raciocínio, 39. O script que gera as variantes está no repositório e roda em um minuto. Cada variante aparece como um modelo separado no `/model`, então a escolha do regime fica com quem está usando.

### 5. Prefira llama.cpp para sessões longas

O engine MLX faz prefill 2 vezes mais rápido, e por isso é tentador. Mas com um prompt de 90 mil tokens ele chegou a 37 GB e reteve 29 depois de responder. O llama.cpp ficou em torno de 26 GB, estável. A decodificação foi igual, cerca de 17 tokens por segundo.

Para um agente de código que acumula contexto por uma hora, estabilidade vence velocidade de prefill. Completa o quadro um guarda de memória: um script que roda a cada 15 segundos e descarrega o modelo se a memória livre cair abaixo de 12 %. Foi ele que impediu o segundo travamento.

### 6. Adapte o modelo ao seu negócio sem treinar nada

Aqui está a parte que interessa a quem quer uma LLM "sua". O caminho não é fine-tuning. Treinar um modelo local sobre saídas de outro modelo viola termos de uso, custa caro e congela conhecimento que muda toda semana. O caminho é dar ao modelo o contexto certo, na hora certa, em duas camadas:

- **Camada determinística.** Convenções do projeto, decisões de arquitetura e lições de tarefas anteriores em arquivos Markdown que entram no plano de cada tarefa. O modelo local segue melhor o que está dentro do plano do que o que precisa buscar.
- **Camada de recuperação.** Um servidor MCP de 80 linhas que indexa esses arquivos com embeddings gerados pelo próprio LM Studio e expõe uma tool de busca ao Claude Code. Serve para o corpus que não cabe no contexto: documentação interna, histórico de decisões, base de conhecimento de atendimento.

Um segundo servidor MCP dá acesso à internet ao modelo local, porque a busca nativa do Claude Code depende da API da Anthropic e não funciona com modelo local.

### 7. Meça com as suas tarefas, não com benchmark

O que decide se a stack vai para o dia a dia é uma avaliação com trabalho real. Montei um harness que pega cards já entregues do projeto, volta ao commit anterior, entrega ao modelo a especificação do card como plano e avalia com lint, typecheck, build e os testes de referência do commit real. Execução autônoma, sem ninguém no loop. Modelo em 4 bits, engine llama.cpp.

| Card | Regime | Tempo | Resultado |
|---|---|---|---|
| Débito de UI + JSON-LD | sem raciocínio | 15,5 min | 54/54 testes |
| idem | raciocínio breve | 36 min | 54/54 |
| idem | raciocínio máximo | 55 min | 54/54 |
| Bug P1: estados de erro em 7 arquivos | sem raciocínio | 28 min | build quebrou: hook client em server component |
| idem | raciocínio breve | 68 min | 41/41 e2e, 19/19 unitários |
| Feature: tema claro, alternador e CSP | sem raciocínio | 23 min | 60/60 |
| idem | raciocínio breve | 90 min (timeout) | incompleto |
| Card vivo: lint de acessibilidade e git hooks | sem raciocínio | 12,5 min (cap de 60 turnos) | incompleto: dependências e ESLint ok, hooks não |
| idem | raciocínio breve | 56 min (cap de 60 turnos) | incompleto: lint e typecheck ok, hooks não, testes quebrados |

Cinco de sete replays entregaram. O card vivo, o único sem gabarito, não saiu em nenhum regime: os dois gastaram perto de 40 % dos turnos aprendendo ferramentas que não conheciam e caíram na mesma armadilha de dependências. Cada linha é uma execução só; leia como evidência, não como benchmark.

O que esses números ensinam sobre operação:

- **Sem raciocínio é o padrão** para tarefas bem especificadas. Mais rápido, acertou 2 de 3 replays.
- **Raciocínio breve para decisões de arquitetura.** No bug P1, foi o único que criou o componente certo. Em troca, pode deliberar demais.
- **O plano precisa trazer o "como".** O modelo local não errou lógica; errou o que não sabia sobre o projeto. Versão da biblioteca, flag do instalador, trecho de configuração: isso vai no plano ou na camada de recuperação, e a tarefa entrega.

### O que levar daqui

Um modelo local útil para o negócio é 20 % modelo e 80 % operação: perfil de memória, controle de raciocínio, contexto do projeto entregue na hora certa e uma avaliação com tarefas reais. Na Cernyn chamamos isso de engenharia desde o experimento: um ciclo curto, com critério de aceite verificável, antes de escalar o investimento. O resultado do ciclo é evidência, não promessa.

Roteador, scripts, servidores MCP, harness de avaliação e todas as decisões, com o que foi refutado: https://github.com/vieiradiego/cernyn-llm-local-router (MIT).

## EN

**How to run a local LLM that does real work for your business: what to install, what to configure, and the five traps that only show up with numbers.**

Running a local model stopped being a weekend experiment. A 48 GB MacBook now runs a 27-billion-parameter model that ships tested code, answers customers in Portuguese and keeps every byte on the machine. What most guides skip is the second half: how to make that model work inside your workflow, with your context, and how to know whether it is delivering.

I spent two weeks building this stack and measuring every decision. Below is what I would do again, in order, and what I would avoid. Everything is in an open repository, failed experiments included so nobody repeats them.

### 1. Pick the model's job before the model

The right question is not "which local model is best", it is "what work will it do". My stack has two roles:

- **Code executor.** Receives a plan written by a frontier model (Claude Fable or Opus, in the cloud) and implements it. This is Qwen3.8-27B, 4-bit quantized.
- **Customer service in Portuguese.** Answers customers from company documents, with time to first token under 1 second. This is Gemma 4 26B-A4B, a mixture-of-experts model that activates only 4 billion parameters per token.

The split matters because it sets the memory budget. Two resident models plus context cache is exactly what froze my Mac at 72 GB allocated on a 48 GB machine. The fix is simple and works as a rule: one profile per kind of work, and never two large models loaded at once.

### 2. Install the minimum: LM Studio, a router and one setting

**LM Studio** serves the models behind an OpenAI- and Anthropic-compatible API. Three settings matter: enable the local service so the API answers without the window open, turn on just-in-time loading with auto-eviction of the previous model, and keep the memory guardrail on "strict". The guardrail only acts at load time; what grows afterwards is the prompt cache, and that is what step 4 handles.

**A 170-line HTTP router** on port 4000 decides by model name: requests for `claude-*` go to Anthropic with your credentials untouched; any other name goes to LM Studio. The payoff is using the local model inside the same Claude Code conversation in VS Code, switching with `/model qwen3.8-27b-gguf-nothink` to execute and `/model claude-fable-5-1` to plan. No lost login, subscription or connectors. The router is transparent by default: no parameter changes, no silent model swaps. The single exception is explicit and comes next.

**One VS Code setting**: point `ANTHROPIC_BASE_URL` at `http://localhost:4000` in the Claude Code extension. That is all.

### 3. Cut what overflows the context

With five claude.ai connectors enabled, Claude Code sent 152 tool definitions in every request. 117 of them were Notion, Gmail and HubSpot schemas: close to 100K tokens before the first message. A 27B model with a 119K window cannot take a single turn.

The router strips only those connector tools on the local path. The payload drops from 534 KB to 154 KB and the model starts working. The cloud path is untouched. This is the kind of adjustment that must be your documented decision, not hidden behavior.

### 4. Control reasoning through the template, not the API

Qwen3.8's chat template defaults to maximum reasoning, and LM Studio ignores the API parameters that would turn it off. I tested all of them, on both engines. The way out was variants of the chat template itself, same weights: one with no reasoning, one with brief reasoning, one with the default.

Same task: at maximum the model had not finished thinking after 4 minutes. Brief reasoning, 57 seconds. No reasoning, 39. The script that builds the variants is in the repository and runs in a minute. Each variant shows up as a separate model in `/model`, so the choice of regime stays with the person using it.

### 5. Prefer llama.cpp for long sessions

The MLX engine prefills 2x faster, which makes it tempting. But on a 90K-token prompt it peaked at 37 GB and kept 29 after answering. llama.cpp stayed around 26 GB, flat. Decode was the same, about 17 tokens per second.

For a coding agent that accumulates context for an hour, stability beats prefill speed. A memory guard completes the picture: a script that runs every 15 seconds and unloads the model if free memory drops below 12%. It is what prevented the second freeze.

### 6. Adapt the model to your business without training anything

This is the part for anyone who wants an LLM that is "theirs". The path is not fine-tuning. Training a local model on another model's outputs violates terms of use, costs money and freezes knowledge that changes every week. The path is giving the model the right context at the right time, in two layers:

- **Deterministic layer.** Project conventions, architecture decisions and lessons from previous tasks, as Markdown files that go into each task's plan. The local model follows what is inside the plan far better than what it has to look up.
- **Retrieval layer.** An 80-line MCP server that indexes those files with embeddings generated by LM Studio itself and exposes a search tool to Claude Code. It covers the corpus that does not fit in context: internal documentation, decision history, a customer-service knowledge base.

A second MCP server gives the local model internet access, because Claude Code's built-in web search depends on the Anthropic API and does not work with a local model.

### 7. Measure with your own tasks, not benchmarks

What decides whether the stack goes into daily use is an evaluation on real work. I built a harness that takes cards already shipped in the project, resets to the parent commit, hands the model the card's spec as its plan and grades with lint, typecheck, build and the reference tests from the real commit. Autonomous runs, nobody in the loop. 4-bit model, llama.cpp engine.

| Card | Regime | Time | Result |
|---|---|---|---|
| UI debt + JSON-LD | no reasoning | 15.5 min | 54/54 tests |
| same | brief reasoning | 36 min | 54/54 |
| same | max reasoning | 55 min | 54/54 |
| P1 bug: error states across 7 files | no reasoning | 28 min | build broke: client hook in a server component |
| same | brief reasoning | 68 min | 41/41 e2e, 19/19 unit |
| Feature: light theme, toggle and CSP | no reasoning | 23 min | 60/60 |
| same | brief reasoning | 90 min (timeout) | incomplete |
| Live card: a11y lint + git hooks | no reasoning | 12.5 min (60-turn cap) | incomplete: deps and ESLint ok, hooks missing |
| same | brief reasoning | 56 min (60-turn cap) | incomplete: lint and typecheck ok, hooks missing, tests broken |

Five of seven replays shipped. The live card, the only one without a known answer, shipped in neither regime: both spent close to 40% of their turns learning unfamiliar tools and fell into the same dependency trap. Every row is a single run; read it as evidence, not as a benchmark.

What these numbers teach about operation:

- **No reasoning is the default** for well-specified tasks. Fastest, shipped 2 of 3 replays.
- **Brief reasoning for architecture decisions.** On the P1 bug it was the only regime that created the right component. The price is occasional over-deliberation.
- **The plan must carry the "how".** The local model did not fail at logic; it failed at what it did not know about the project. Library version, installer flag, config snippet: put that in the plan or the retrieval layer and the task ships.

### What to take away

A local model that is useful to a business is 20% model and 80% operation: memory profile, reasoning control, project context delivered at the right time, and an evaluation on real tasks. At Cernyn we call this engineering from the experiment: a short cycle with a verifiable acceptance criterion before scaling the investment. The output of that cycle is evidence, not a promise.

Router, scripts, MCP servers, evaluation harness and every decision, including what was refuted: https://github.com/vieiradiego/cernyn-llm-local-router (MIT).

## Post curto para o feed (PT-BR)

> Gancho na primeira linha: o LinkedIn corta em cerca de 210 caracteres.

Um LLM local útil para o negócio é 20 % modelo e 80 % operação. Passei duas semanas medindo isso num Mac de 48 GB. Sete passos, com número.

1. Escolha o papel antes do modelo: executor de código (Qwen3.8-27B) ou atendimento em português (Gemma 4). Nunca os dois carregados juntos. Foi o que travou meu Mac com 72 GB alocados.

2. Instale o mínimo: LM Studio, um roteador de 170 linhas e uma configuração no VS Code. O modelo local entra na mesma conversa do Claude Code, com `/model`, sem perder login nem connectors.

3. Corte o que estoura o contexto: com connectors ligados, o Claude Code manda 152 tools por requisição. São 100 mil tokens. O roteador remove só isso no caminho local.

4. Controle o raciocínio pelo template: 4 minutos pensando no padrão, 57 segundos com raciocínio breve, 39 sem. Mesmos pesos.

5. llama.cpp para sessões longas: MLX chegou a 37 GB num prompt de 90 mil tokens; llama.cpp ficou em 26.

6. Adapte ao seu negócio sem treinar: convenções e decisões dentro do plano, mais um MCP de busca sobre a documentação interna.

7. Meça com as suas tarefas: 5 de 7 cards reais entregues, autônomo. O que falhou, falhou por não conhecer o projeto. Isso o plano resolve.

Tudo aberto, com os erros registrados: github.com/vieiradiego/cernyn-llm-local-router

#IAAgentica #EngenhariaDigital #LLMLocal

## Short feed post (EN)

A local LLM that is useful to a business is 20% model and 80% operation. I spent two weeks measuring that on a 48 GB Mac. Seven steps, with numbers.

1. Pick the job before the model: code executor (Qwen3.8-27B) or customer service (Gemma 4). Never both loaded at once. That is what froze my Mac at 72 GB allocated.

2. Install the minimum: LM Studio, a 170-line router and one VS Code setting. The local model joins the same Claude Code conversation through `/model`, keeping login and connectors.

3. Cut what overflows the context: with connectors on, Claude Code sends 152 tools per request. That is 100K tokens. The router strips only those on the local path.

4. Control reasoning through the template: 4 minutes thinking by default, 57 seconds with brief reasoning, 39 with none. Same weights.

5. llama.cpp for long sessions: MLX peaked at 37 GB on a 90K prompt; llama.cpp stayed at 26.

6. Adapt to your business without training: conventions and decisions inside the plan, plus a search MCP over internal docs.

7. Measure with your own tasks: 5 of 7 real cards shipped, autonomously. What failed, failed for not knowing the project. The plan fixes that.

All open, mistakes included: github.com/vieiradiego/cernyn-llm-local-router

#AgenticAI #LocalLLM #ClaudeCode
