#!/bin/sh
# Aceite unitário pós-hoc: copia os arquivos ACCEPT_UNIT do REF_SHA para a worktree do run e
# roda vitest neles. Uso: evals/accept-unit.sh <TAREFA> <regime>
# (Separado do run.sh para poder ser executado sem editar o harness durante um run em curso.)
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd); TASK="${1:?tarefa}"; REGIME="${2:?regime}"
. "$HERE/evals/coding/tarefas/$TASK.env"; W="${EVAL_ROOT:-$HOME/.cache/local-llm/worktrees/$(basename "$REPO")}/$TASK-$REGIME"; OUT="$HERE/evals/results/$TASK-$REGIME"
[ -n "${ACCEPT_UNIT:-}" ] && [ -n "${REF_SHA:-}" ] || { echo "sem ACCEPT_UNIT/REF_SHA para $TASK"; exit 0; }
cd "$W" || exit 1
for t in $ACCEPT_UNIT; do git -C "$REPO" show "$REF_SHA:$t" > "$W/$t"; done
npx vitest run $ACCEPT_UNIT > "$OUT/unit.log" 2>&1; RC=$?
RES=$(grep -oE "Tests +[0-9]+ passed|[0-9]+ failed|[0-9]+ passed" "$OUT/unit.log" | tr '\n' ' ')
git checkout -q -- $ACCEPT_UNIT 2>/dev/null
echo "| unit de referência ($ACCEPT_UNIT) | ${RES:-rc=$RC} |" >> "$OUT/report.md"
echo "$TASK × $REGIME — unit de referência: ${RES:-rc=$RC}"
