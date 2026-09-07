#!/bin/sh
# Sonda de saúde do modelo de atendimento. Rodar em loop (ex.: a cada 60s via cron,
# launchd agent do usuário, ou `while true; do bin/healthcheck.sh; sleep 60; done`).
#
# Duas checagens:
#   1. /v1/models responde e lista o modelo de atendimento;
#   2. uma completion mínima volta em tempo hábil (o modelo está mesmo inferindo,
#      não só carregado).
#
# Em falha: tenta recarregar via lms e notifica no macOS. Estado (contagem de falhas
# consecutivas) fica em arquivo para sobreviver entre execuções.

set -u

PORT=1234
MODEL="${ATENDIMENTO_MODEL:-gemma-4-26b-a4b-it-qat}"
# Só vigia/recarrega o Gemma se o perfil de atendimento estiver ativo (arquivo-flag criado
# por `bin/serve.sh --atendimento`). Em perfil dev, recarregar o Gemma somaria 15,6 GB e
# repetiria o incidente de memória de 06/09/2026.
FLAG="/tmp/local-llm-atendimento.on"
if [ ! -f "$FLAG" ]; then
    curl -sf --max-time 3 -H "x-api-key: x" "http://localhost:4000/v1/models" >/dev/null 2>&1 \
        || launchctl kickstart -k "gui/$(id -u)/com.local-llm.router" 2>/dev/null || true
    exit 0
fi
STATE="/tmp/local-llm-healthcheck.fails"
MAX_FAILS=2
TIMEOUT=30

fails=$(cat "$STATE" 2>/dev/null || echo 0)

check() {
    curl -sf --max-time 5 "http://localhost:${PORT}/v1/models" | grep -q "$MODEL" || return 1
    curl -sf --max-time "$TIMEOUT" "http://localhost:${PORT}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"${MODEL}\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" \
        >/dev/null || return 1
    return 0
}

# roteador (LaunchAgent): se caiu, kickstart — a extensão do VS Code depende dele
if ! curl -sf --max-time 3 -H "x-api-key: x" "http://localhost:4000/v1/models" >/dev/null 2>&1; then
    echo "healthcheck: roteador fora — kickstart" >&2
    launchctl kickstart -k "gui/$(id -u)/com.local-llm.router" 2>/dev/null || true
fi

if check; then
    echo 0 > "$STATE"
    exit 0
fi

fails=$((fails + 1))
echo "$fails" > "$STATE"
echo "healthcheck: falha ${fails}/${MAX_FAILS} para ${MODEL}" >&2

if [ "$fails" -ge "$MAX_FAILS" ]; then
    osascript -e "display notification \"Recarregando ${MODEL} (${fails} falhas)\" with title \"local-llm: atendimento fora do ar\"" 2>/dev/null || true
    if command -v lms >/dev/null 2>&1; then
        lms unload "$MODEL" 2>/dev/null || true
        lms load "$MODEL" --ttl 0 && echo 0 > "$STATE" && echo "healthcheck: ${MODEL} recarregado" >&2
    else
        echo "healthcheck: 'lms' não está no PATH — recarga manual necessária" >&2
    fi
fi
exit 1
