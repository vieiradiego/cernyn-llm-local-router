#!/bin/sh
# Harness de avaliação do executor local — replay de um card com gabarito.
#
# Uso: evals/run.sh <TAREFA> <regime> [max_turns] [max_min]
#   TAREFA  = nome em evals/coding/tarefas/<TAREFA>.md (+ .env com REPO, BASE_SHA, REF_SHA, ACCEPT_E2E…)
#   regime  = nothink | low | base   → qwen3.8-27b-nothink | qwen3.8-27b-low | qwen3.8-27b
#
# O que faz: worktree limpa em BASE_SHA (node_modules por clone APFS), copia o plano para
# docs/plans/, roda `claude -p` via roteador (localhost:4000) com o modelo do regime, mede
# tempo/turnos/tokens, depois aplica o aceite: npm run check, npm run build, e os testes de
# referência (copiados do REF_SHA) com Playwright. Resultado em evals/results/<TAREFA>-<regime>.md
# e uma linha em evals/results.md. A worktree é DESTACADA (sem branch) e vive FORA do repo-alvo
# (EVAL_ROOT, padrão ~/.cache/local-llm/worktrees/<repo>); é removida ao final — o diff fica em
# evals/results/<TAREFA>-<regime>/diff.patch. KEEP_WORKTREE=1 mantém para revisão manual.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
TASK="${1:?tarefa}"; REGIME="${2:?regime}"; MAX_TURNS="${3:-60}"; MAX_MIN="${4:-45}"
ENGINE="${ENGINE:-gguf}"   # gguf (llama.cpp, memória previsível — padrão para sessões longas) | mlx
case "$REGIME" in nothink|low|base) ;; *) echo "regime inválido"; exit 2;; esac
if [ "$ENGINE" = "mlx" ]; then
    case "$REGIME" in nothink) MODEL=qwen3.8-27b-nothink;; low) MODEL=qwen3.8-27b-low;; base) MODEL=qwen3.8-27b;; esac
else
    # chaves do índice do LM Studio (lms ls): as variantes GGUF compartilham a chave com as MLX,
    # distinguidas pelo sufixo de quantização; o --identifier torna o nome único na API.
    case "$REGIME" in base) KEY="qwen3.8-27b-base"; MODEL=qwen3.8-27b-gguf;; low) KEY="qwen3.8-27b-low@q4_k_s"; MODEL=qwen3.8-27b-gguf-low;; nothink) KEY="qwen3.8-27b-nothink@q4_k_s"; MODEL=qwen3.8-27b-gguf-nothink;; esac
fi
PLAN="$HERE/evals/coding/tarefas/$TASK.md"; ENVF="$HERE/evals/coding/tarefas/$TASK.env"
[ -f "$PLAN" ] && [ -f "$ENVF" ] || { echo "faltam $PLAN / $ENVF"; exit 2; }
. "$ENVF"
export PATH="$HOME/.local/bin:$HOME/.lmstudio/bin:$PATH"; unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
STAMP=$(date +%Y%m%d-%H%M); OUT="$HERE/evals/results/$TASK-$REGIME"; mkdir -p "$OUT"
EVAL_ROOT="${EVAL_ROOT:-$HOME/.cache/local-llm/worktrees/$(basename "$REPO")}"; mkdir -p "$EVAL_ROOT"
W="$EVAL_ROOT/$TASK-$REGIME"

echo "== $TASK × $REGIME ($MODEL, engine $ENGINE) — worktree em $BASE_SHA =="
# executor com limites explícitos: 1 slot, contexto 131072 (GGUF) — descarrega outros Qwen antes
if [ "$ENGINE" = "gguf" ]; then
    for m in $("$HOME/.lmstudio/bin/lms" ps 2>/dev/null | awk 'NR>2 && $1 ~ /^qwen3\.8-27b/ {print $1}'); do [ "$m" = "$MODEL" ] || "$HOME/.lmstudio/bin/lms" unload "$m" >/dev/null 2>&1; done
    "$HOME/.lmstudio/bin/lms" ps 2>/dev/null | awk 'NR>2{print $1}' | grep -qx "$MODEL" || "$HOME/.lmstudio/bin/lms" load "$KEY" -c 131072 --parallel 1 --ttl 7200 --identifier "$MODEL" --yes 2>&1 | tr '\r' '\n' | grep -E "loaded|rror" | tail -1
fi
git -C "$REPO" worktree remove --force "$W" 2>/dev/null; git -C "$REPO" worktree prune
git -C "$REPO" worktree add -q --detach "$W" "$BASE_SHA" || exit 1   # destacada: nenhum branch no repo-alvo
cp -Rc "$REPO/node_modules" "$W/node_modules"
mkdir -p "$W/docs/plans" && cp "$PLAN" "$W/docs/plans/$TASK.md"
git -C "$W" add -A >/dev/null 2>&1; git -C "$W" commit -qm "eval: plano $TASK" >/dev/null 2>&1   # baseline com o plano (para o diff ser só do executor)

# --- execução ------------------------------------------------------------------------------
PROMPT="Implemente docs/plans/$TASK.md. Siga o plano à risca: escopo, restrições e passos na ordem. Ao terminar, rode o critério de aceite (npm run check e npm run build) e mostre o resultado. Se algo do plano não funcionar, PARE e relate — não replaneje. Não faça commit."
ROUTER_LOG=/tmp/local-llm-router.log; L0=$(wc -l < "$ROUTER_LOG" 2>/dev/null || echo 0)
echo "== executor: $MODEL, max $MAX_TURNS turnos, $MAX_MIN min =="; S=$(date +%s)
# amostrador de memória: footprint do engine MLX + % livre do sistema, a cada 30 s
( while :; do pid=$(ps -axo pid,rss,comm | grep -iE "lmstudio|lm studio|llama|mlx" | grep -v grep | sort -k2 -rn | head -1 | awk '{print $1}'); fp=$( [ -n "$pid" ] && footprint -p "$pid" 2>/dev/null | awk '/phys_footprint:/{print $2$3}'); fr=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free/{print $2}'); echo "$(date +%H:%M:%S) engine=${fp:-?} livre=${fr:-?}"; sleep 30; done ) > "$OUT/mem.log" 2>/dev/null & MPID=$!
( cd "$W" && ANTHROPIC_BASE_URL=http://localhost:4000 claude -p "$PROMPT" --model "$MODEL" --max-turns "$MAX_TURNS" \
    --output-format json --permission-mode acceptEdits \
    --allowedTools "Read,Edit,Write,MultiEdit,Glob,Grep,Bash(npm run:*),Bash(npm install:*),Bash(npm ci:*),Bash(npx:*),Bash(git diff:*),Bash(git status:*),Bash(ls:*),Bash(cat:*),Bash(head:*),Bash(wc:*),Bash(grep:*),mcp__knowledge__search_knowledge,mcp__web__search_web,mcp__web__fetch_page" \
    < /dev/null > "$OUT/claude.json" 2> "$OUT/claude.err" ) & CPID=$!
n=0; while kill -0 $CPID 2>/dev/null && [ $n -lt $((MAX_MIN*60)) ]; do sleep 10; n=$((n+10)); done
TIMED_OUT=0; if kill -0 $CPID 2>/dev/null; then TIMED_OUT=1; kill $CPID 2>/dev/null; pkill -f "claude -p Implemente docs/plans/$TASK" 2>/dev/null; fi
wait $CPID 2>/dev/null; E=$(date +%s); DUR=$((E-S)); kill $MPID 2>/dev/null
MEMPEAK=$(awk '{gsub("engine=","",$2); print $2}' "$OUT/mem.log" | grep -E "GB$" | sort -n | tail -1); MEMMIN=$(awk '{gsub("livre=","",$3); print $3}' "$OUT/mem.log" | tr -d '%' | sort -n | head -1)
GUARD=$(grep -c "$(date +%F)" /tmp/local-llm-memguard.log 2>/dev/null || echo 0)
L1=$(wc -l < "$ROUTER_LOG" 2>/dev/null || echo 0)
REQS=$(sed -n "$((L0+1)),${L1}p" "$ROUTER_LOG" | grep -c "→ localhost"); ERRS=$(sed -n "$((L0+1)),${L1}p" "$ROUTER_LOG" | grep -cE "\[(4|5)[0-9][0-9]\] $MODEL")
TURNS=$(python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1])); print(d.get("num_turns","?"))
except Exception: print("?")' "$OUT/claude.json")
RESULT=$(python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1])); print((d.get("result") or "")[:600].replace("\n"," "))
except Exception: print("(sem JSON — timeout ou erro)")' "$OUT/claude.json")

# --- aceite --------------------------------------------------------------------------------
cd "$W"
git add -A >/dev/null 2>&1; FILES=$(git diff --cached --stat HEAD | tail -1); git diff --cached HEAD > "$OUT/diff.patch"; git reset -q >/dev/null 2>&1
VIOL=""; for f in $FORBIDDEN; do git diff --name-only HEAD -- "$f" 2>/dev/null | grep -q . && VIOL="$VIOL $f"; done
echo "== aceite: npm run check =="; npm run check > "$OUT/check.log" 2>&1; CHECK=$?
echo "== aceite: npm run build =="; npm run build > "$OUT/build.log" 2>&1; BUILD=$?
E2E="n/a"; if [ -n "${ACCEPT_E2E:-}" ] && [ -n "${REF_SHA:-}" ]; then
    for t in $ACCEPT_E2E; do git -C "$REPO" show "$REF_SHA:$t" > "$W/$t"; done   # testes de referência (ocultos)
    npx playwright test $ACCEPT_E2E > "$OUT/e2e.log" 2>&1; E2E_RC=$?
    E2E=$(grep -oE "[0-9]+ passed|[0-9]+ failed|[0-9]+ skipped" "$OUT/e2e.log" | tr '\n' ' '); [ -z "$E2E" ] && E2E="rc=$E2E_RC"
    git checkout -q -- $ACCEPT_E2E 2>/dev/null   # restaura o que o executor deixou
fi

ACC="n/a"; if [ -n "${ACCEPT_CMD:-}" ]; then (cd "$W" && sh -c "$ACCEPT_CMD") > "$OUT/accept.log" 2>&1 && ACC="✓" || ACC="✗ (ver accept.log)"; fi

# --- relatório -----------------------------------------------------------------------------
{
echo "# $TASK × $REGIME ($MODEL, engine $ENGINE) — $STAMP"
echo; echo "| métrica | valor |"; echo "|---|---|"
echo "| duração | $((DUR/60)) min $((DUR%60)) s$( [ $TIMED_OUT = 1 ] && echo ' (TIMEOUT)') |"
echo "| turnos (num_turns) | $TURNS |"; echo "| requisições ao modelo / erros 4xx-5xx | $REQS / $ERRS |"
echo "| diff | ${FILES:-vazio} |"; echo "| arquivos proibidos tocados | ${VIOL:-nenhum} |"
echo "| npm run check | $( [ $CHECK = 0 ] && echo ✓ || echo "✗ (rc $CHECK)") |"
echo "| npm run build | $( [ $BUILD = 0 ] && echo ✓ || echo "✗ (rc $BUILD)") |"
echo "| e2e de referência ($ACCEPT_E2E) | $E2E |"; echo "| aceite específico (ACCEPT_CMD) | $ACC |"
echo "| memória: pico do engine / mínimo livre | ${MEMPEAK:-?} / ${MEMMIN:-?}% |"; echo "| ações do memguard hoje (ver /tmp/local-llm-memguard.log) | $GUARD |"
echo; echo "## Mensagem final do executor"; echo; echo "$RESULT"
echo; echo "Worktree: \`$W\`$( [ "${KEEP_WORKTREE:-0}" = 1 ] && echo " (mantida, KEEP_WORKTREE=1)" || echo " (removida; diff em diff.patch)"). Logs: \`$OUT/\`."
} > "$OUT/report.md"
[ "${KEEP_WORKTREE:-0}" = 1 ] || { git -C "$REPO" worktree remove --force "$W" >/dev/null 2>&1; git -C "$REPO" worktree prune; }
printf '| %s | %s/%s | %s | %s | %s | %s | %s | %s | %s |\n' "$TASK" "$REGIME" "$ENGINE" "$((DUR/60))m$( [ $TIMED_OUT = 1 ] && echo '(TO)')" "$TURNS" "$REQS/$ERRS" "$( [ $CHECK = 0 ] && echo ✓ || echo ✗)" "$( [ $BUILD = 0 ] && echo ✓ || echo ✗)" "$E2E" "${VIOL:-—}" >> "$HERE/evals/results/replays.md"
cat "$OUT/report.md"
