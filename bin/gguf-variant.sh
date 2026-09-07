#!/bin/sh
# Variante de template de um GGUF (para o engine llama.cpp): copia o arquivo com o
# tokenizer.chat_template alterado, via gguf-new-metadata (~16 GB por variante em disco).
# Uso: bin/gguf-variant.sh <arquivo.gguf> <base|low|nothink> <dir-destino>
# Todos os modos aplicam a correção "system em qualquer posição": o Claude Code envia uma
# mensagem role=system depois da do usuário e o template original faz raise_exception —
# o renderizador do MLX tolera, o minja do llama.cpp não (medido 07/09/2026).
set -eu
SRC="$1"; MODE="$2"; DST="$3"; HERE=$(cd "$(dirname "$0")/.." && pwd); V="$HERE/mcp/.venv/bin"
mkdir -p "$DST"; OUT="$DST/$(basename "$SRC" .gguf)-$MODE.gguf"; T=$(mktemp)
"$V/python" - "$SRC" "$MODE" "$T" <<'PYEOF'
import sys
from gguf import GGUFReader
src, mode, out = sys.argv[1:4]
r = GGUFReader(src, "r"); f = r.fields["tokenizer.chat_template"]
tmpl = bytes(f.parts[f.data[0]]).decode("utf-8")
RAISE = "{{- raise_exception('System message must be at the beginning.') }}"
assert RAISE in tmpl, "template sem a checagem de system"
new = tmpl.replace(RAISE, "{{- '<|im_start|>system\\n' + content + '<|im_end|>\\n' }}")
if mode == "low":
    assert "reasoning_effort|default('xhigh')" in new, "template sem reasoning_effort xhigh"
    new = new.replace("reasoning_effort|default('xhigh')", "reasoning_effort|default('low')")
elif mode == "nothink":
    new = "{%- set enable_thinking = false %}\n" + new
elif mode != "base": raise SystemExit("modo inválido: base | low | nothink")
open(out, "w").write(new); print(f"template: {len(tmpl)} → {len(new)} chars")
PYEOF
"$V/gguf-new-metadata" "$SRC" "$OUT" --chat-template-file "$T" --force && echo "ok: $OUT"; rm -f "$T"
