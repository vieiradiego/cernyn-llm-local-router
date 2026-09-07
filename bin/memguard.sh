#!/bin/sh
# Guarda de memória (pós-incidente 06/09/2026: LM Studio a 72 GB em 48 GB de RAM).
# O engine MLX acumula KV cache + "prompt cache store" em memória de GPU sem teto útil
# (cap de 163 GB) e o guardrail do LM Studio só age no LOAD, não no crescimento.
# Este guarda roda a cada 30 s (LaunchAgent) e, se a memória livre do sistema cair abaixo
# de MIN_FREE_PCT ou o engine passar de MAX_ENGINE_GB, descarrega as variantes JIT do Qwen
# (o próximo /model recarrega em ~7 s, com cache limpo). Gemma/BGE explícitos não são tocados
# a menos que a situação seja crítica (CRIT_FREE_PCT).
set -u
MIN_FREE_PCT="${MEMGUARD_MIN_FREE_PCT:-15}"
CRIT_FREE_PCT="${MEMGUARD_CRIT_FREE_PCT:-8}"
MAX_ENGINE_GB="${MEMGUARD_MAX_ENGINE_GB:-34}"
LMS="$HOME/.lmstudio/bin/lms"
LOG="/tmp/local-llm-memguard.log"

free_pct=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/{gsub(/%/,"",$2); print int($2)}')
pid=$(ps -axo pid,rss,comm | grep -iE "lmstudio|lm studio|llama|mlx" | grep -v grep | sort -k2 -rn | head -1 | awk '{print $1}')
eng_gb=0
[ -n "${pid:-}" ] && eng_gb=$(footprint -p "$pid" 2>/dev/null | awk '/phys_footprint:/{v=$2; u=$3; if(u=="GB") print int(v); else if(u=="MB") print int(v/1024); else print 0}')
[ -z "$free_pct" ] && exit 0

loaded_qwen() { curl -sf --max-time 3 "http://localhost:1234/api/v0/models" | python3 -c 'import json,sys; d=json.load(sys.stdin); ms=d.get("data",d); print(" ".join(m["id"] for m in ms if m.get("state")=="loaded" and m["id"].startswith("qwen3.8-27b")))' 2>/dev/null; }
loaded_all()  { curl -sf --max-time 3 "http://localhost:1234/api/v0/models" | python3 -c 'import json,sys; d=json.load(sys.stdin); ms=d.get("data",d); print(" ".join(m["id"] for m in ms if m.get("state")=="loaded"))' 2>/dev/null; }

if [ "$free_pct" -lt "$CRIT_FREE_PCT" ]; then
    echo "$(date '+%F %T') CRÍTICO: livre=${free_pct}% engine=${eng_gb}GB → descarregando TUDO" >> "$LOG"
    for m in $(loaded_all); do "$LMS" unload "$m" >/dev/null 2>&1; done
    osascript -e 'display notification "Memória crítica: modelos descarregados" with title "local-llm memguard"' 2>/dev/null
elif [ "$free_pct" -lt "$MIN_FREE_PCT" ] || [ "${eng_gb:-0}" -gt "$MAX_ENGINE_GB" ]; then
    q=$(loaded_qwen)
    if [ -n "$q" ]; then
        echo "$(date '+%F %T') AVISO: livre=${free_pct}% engine=${eng_gb}GB → descarregando Qwen ($q)" >> "$LOG"
        for m in $q; do "$LMS" unload "$m" >/dev/null 2>&1; done
        osascript -e "display notification \"Qwen descarregado (livre ${free_pct}%, engine ${eng_gb} GB). Próximo /model recarrega.\" with title \"local-llm memguard\"" 2>/dev/null
    fi
fi
exit 0
