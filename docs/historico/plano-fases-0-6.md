> **Cópia histórica** do plano aprovado (fases 0–6), preservada como estava em `~/.claude/plans/purring-stargazing-puffin.md`. Referências a `models.md` apontam hoje para `docs/modelos.md`. Estado atual: `docs/01..04`.

# Fase 6 — VS Code + pipeline de conhecimento do Fable

## Contexto

A stack base (fases 0-5) está **operacional e verificada**: LM Studio servindo
`qwen3.8-27b` (executor, ~17 tok/s), `gemma-4-26b-a4b-it-qat` (atendimento, 46 tok/s
aquecido) e `text-embedding-bge-m3` (dim 1024) em `localhost:1234`; `bin/claude-local`
validado ponta a ponta (criou arquivo via Claude Code → Qwen local, 0 intervenções).
Histórico completo da seleção de modelos: `models.md` e `evals/results.md` no repo.

Esta fase responde dois pedidos novos do usuário:

1. **Usar os LLMs locais no Claude Code e no VS Code** — hoje só existe o launcher de
   terminal.
2. **"Evoluir o RAG com o conhecimento de desenvolvimento do Fable 5"** — avaliado e
   redesenhado: a ideia é correta na direção (o executor local falha por falta de contexto
   e convenções), mas o mecanismo de maior alavancagem para um agente Claude Code não é
   RAG vetorial, é **conhecimento determinístico** (CLAUDE.md, planos, lições) carregado
   sempre; RAG entra como camada 2 para o corpus que não cabe no contexto. Decisão do
   usuário: **camadas 1+2 completas**.

### Calibração: onde o executor local está vs. a fronteira (set/2026)

Pergunta do usuário respondida com números atuais — **não há equivalência com Fable/Opus 5**,
mas o tier é o certo para o papel:

| SWE-bench Pro | Score | Papel na stack |
|---|---|---|
| Fable 5 | 80,3% | planeja (nuvem) |
| Opus 5 | 79,2% | planeja (nuvem) |
| Sonnet 5 | 63,2% | — |
| **Qwen3.8-27B (local)** | **61,7%** | executa |

Terminal Bench 2.1: Sonnet 5 80,4% · Qwen3.8 73,0%. Leitura: o executor local é
~classe Sonnet 5 em coding agêntico — o tier que a própria Anthropic posiciona para
execução. Caveats mantidos: números do Qwen são vendor-reported (comparados contra Opus
4.6, duas gerações atrás), o quant 4-bit perde 1-3 pontos, e benchmark superestima a
confiabilidade agêntica real do local (gap de intervenções não aparece em score). O juiz
continua sendo a eval A/B da verificação 5, com tarefas reais.

Três fatos que moldam o desenho:

- O "RAG do LM Studio" (chat com documentos) é **só da UI** — não existe pela API. O
  caminho programático é o `/v1/embeddings` (BGE-M3, já residente) + store próprio,
  exposto ao Claude Code via **MCP server local**. O mesmo store servirá depois ao bot
  de atendimento.
- RAG transfere *conhecimento*, não *raciocínio*. O gap medido do executor (aderência a
  restrições, qualidade de decisão) não some com retrieval — o que some é o erro por
  "não conhecia a convenção/decisão X". Expectativa calibrada nas evals.
- Fronteira legal: usar planos/revisões que o Fable escreveu para o usuário como
  **contexto/RAG é uso normal do próprio produto de trabalho**; **fine-tunar** modelo
  local sobre outputs do Claude violaria os termos da Anthropic. Tudo abaixo fica no
  lado permitido (retrieval, nunca treino).

## Parte A — VS Code (duas vias, autocomplete adiado)

**A1. Terminal integrado (via principal, zero mudança).** `bin/claude-local` já funciona
em qualquer terminal do VS Code; a extensão Claude Code segue na nuvem para planejar.
Entregável: seção "VS Code" no `README.md` documentando o fluxo lado a lado (extensão
planeja com Fable/Opus → salva `docs/plans/<tarefa>.md` → terminal roda
`bin/claude-local` para executar).

**A2. Workspace dedicado do executor.** Criar `vscode/executor.code-workspace` no repo
`local-llm` com as settings da extensão apontando para o servidor local — **escopo de
workspace, nunca de usuário** (em user settings redirecionaria também as sessões de
planejamento, mesma armadilha já documentada na fase 3):

```jsonc
// vscode/executor.code-workspace (folders: caminhos dos projetos-alvo)
{
  "folders": [{ "path": ".." }],
  "settings": {
    "claudeCode.environmentVariables": [
      { "name": "ANTHROPIC_BASE_URL",    "value": "http://localhost:1234" },
      { "name": "ANTHROPIC_AUTH_TOKEN",  "value": "lmstudio" },
      { "name": "ANTHROPIC_MODEL",       "value": "qwen3.8-27b" },
      { "name": "ANTHROPIC_SMALL_FAST_MODEL", "value": "qwen3.8-27b" },
      { "name": "ANTHROPIC_DEFAULT_OPUS_MODEL",   "value": "qwen3.8-27b" },
      { "name": "ANTHROPIC_DEFAULT_SONNET_MODEL", "value": "qwen3.8-27b" },
      { "name": "ANTHROPIC_DEFAULT_HAIKU_MODEL",  "value": "qwen3.8-27b" },
      { "name": "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS", "value": "1" }
    ]
  }
}
```

Nota aprendida na fase 3: `ANTHROPIC_MODEL` é obrigatório — o modelo fixado no
settings.json global sobrepõe os `DEFAULT_*`.

**A3. Autocomplete local (Continue/Cline): adiado, com registro.** Tab-completion exige
um modelo FIM pequeno sempre quente disputando GPU com os ~30 GB residentes, numa GPU que
já opera no teto de banda durante o executor. Reavaliar depois das evals; anotar no
`models.md` como item futuro (candidato: um Qwen coder ~3B para FIM).

## Parte B — Pipeline de conhecimento (camadas 1+2)

### Camada 1 — determinística (maior ROI)

Estrutura em `knowledge/` no repo `local-llm`, alimentada pelas sessões com Fable/Opus:

```
knowledge/
  conventions/<projeto>.md   ← convenções extraídas das sessões de planejamento/revisão
  lessons.md                 ← lições pós-tarefa (uma entrada por tarefa executada)
  adr/NNN-<decisão>.md       ← decisões de arquitetura, uma por arquivo
```

Fluxo de realimentação (documentar no README — é processo, não código):
1. Fable planeja → plano em `docs/plans/` (já existe).
2. Executor local implementa → revisão do diff (portão da fase 4).
3. **Novo passo**: o que a revisão pegou (violação, convenção ignorada, padrão bom) vira
   entrada em `knowledge/lessons.md`; recorrências são promovidas a
   `conventions/<projeto>.md`.
4. No repo-alvo de cada projeto, o `CLAUDE.md` referencia/incorpora as convenções — o
   executor as recebe *sempre*, sem depender de retrieval.

Template de plano atualizado em `docs/plans/README.md`: todo plano do Fable passa a abrir
com um bloco "Convenções aplicáveis" copiado de `knowledge/conventions/` — conhecimento
empurrado para dentro do contrato, onde o modelo local comprovadamente o vê.

### Camada 2 — MCP server de retrieval

`mcp/knowledge-server/` — servidor MCP em Python (stdio), pequeno e sem framework:

- **Indexação**: `mcp/index.py` varre `knowledge/`, `docs/plans/` e diretórios extras
  configuráveis (ex.: ADRs de outros repos), chunking por seção markdown (~500 tokens),
  embeddings via `POST localhost:1234/v1/embeddings` (modelo `text-embedding-bge-m3`),
  vetores em **sqlite-vec** (`knowledge/.index.db`, um arquivo, sem serviço extra).
  Reindexação incremental por mtime+hash.
- **Servidor**: `mcp/server.py` expõe duas tools MCP:
  - `search_knowledge(query, k=5)` → busca vetorial + filtro por score, retorna chunks
    com fonte (`arquivo#seção`);
  - `list_knowledge()` → inventário do que está indexado (para o modelo saber o que
    pode perguntar).
- **Plug no executor**: bloco `mcpServers` em `.mcp.json` do repo `local-llm` (e
  instrução no README para copiar aos repos-alvo), apontando
  `command: python3 mcp/server.py`. O `claude-local` herda automaticamente.
- **Instrução de uso**: uma linha no template de plano: "antes de implementar, consulte
  `search_knowledge` sobre convenções do módulo afetado" — modelos locais não usam tool
  nova espontaneamente; o plano precisa mandar.

Dependências: `sqlite-vec` e `mcp` (pip, via `mcp/requirements.txt` + venv em `mcp/.venv`).

### O que NÃO fazer (registrado no README)

- Fine-tuning local sobre outputs do Claude — vedado pelos termos; o pipeline é 100%
  retrieval/contexto.
- Plugin big-rag do LM Studio — resolve RAG da UI de chat, não integra com Claude Code;
  nosso MCP cobre o caso com o mesmo modelo de embedding.

## Arquivos a criar/alterar

| Caminho | Ação |
|---|---|
| `vscode/executor.code-workspace` | novo — workspace do executor (A2) |
| `knowledge/{conventions/,lessons.md,adr/}` | novo — camada 1 com templates |
| `mcp/{server.py,index.py,requirements.txt}` | novo — camada 2 |
| `.mcp.json` | novo — registra o knowledge-server |
| `docs/plans/README.md` | editar — template com "Convenções aplicáveis" + instrução de `search_knowledge` |
| `README.md` | editar — seção VS Code, fluxo de realimentação, vedação de fine-tuning |
| `models.md` | editar — nota do FIM/autocomplete adiado |

## Verificação

1. `python3 mcp/index.py` indexa `knowledge/` + `docs/plans/` sem erro e reporta
   contagem de chunks; segunda rodada é incremental (0 novos).
2. Query direta ao índice devolve o chunk certo para uma pergunta sobre convenção
   plantada de propósito (fixture de teste).
3. `claude-local -p "use a tool search_knowledge para responder: <pergunta sobre a
   convenção plantada>"` → o Qwen chama a tool MCP e responde com a fonte correta.
4. Abrir `vscode/executor.code-workspace`, rodar a extensão Claude Code nele e confirmar
   que a sessão responde pelo modelo local (e que num workspace normal segue na nuvem).
5. Eval A/B mínima: repetir 1 tarefa de `evals/coding/` com e sem o bloco "Convenções
   aplicáveis"+MCP, comparando intervenções e violações — registra em `evals/results.md`
   se o pipeline paga o custo.
