#!/bin/sh
# Sobe a stack local (LM Studio) num dos dois PERFIS DE MEMÓRIA:
#   dev (padrão)      BGE-M3 residente; Qwen só via JIT (o /model da extensão carrega e troca).
#   --atendimento     idem + Gemma residente e aquecido (expediente do bot).
# Passos: limite da GPU → servidor → modelos conforme perfil → roteador → warmup → caffeinate.
#
# Uso: bin/serve.sh [--atendimento]   (Ctrl+C encerra o caffeinate; modelos seguem carregados)
#
# Identificadores no LM Studio (lms ps):
#   - executor:    qwen3.8-27b | qwen3.8-27b-low | qwen3.8-27b-nothink  (NUNCA carregar aqui)
#   - atendimento: gemma-4-26b-a4b-it-qat
#   - embeddings:  text-embedding-bge-m3

set -eu

PORT=1234
ATENDIMENTO="${ATENDIMENTO_MODEL:-gemma-4-26b-a4b-it-qat}"
EMBEDDINGS="${EMBEDDINGS_MODEL:-text-embedding-bge-m3}"

# 1. Limite de memória da GPU (0 = padrão ~36 GB; config A precisa de 40 GB)
limit=$(sysctl -n iogpu.wired_limit_mb)
if [ "$limit" -lt 40960 ]; then
    echo "aviso: iogpu.wired_limit_mb=${limit} (<40960). Rode: sudo bin/mem-setup.sh"
    echo "       Prosseguindo mesmo assim — a config B (~25 GB) cabe no padrão."
fi

# 2. Servidor
#    ATENÇÃO: `lms server start` fica pendurado em "Waking up LM Studio service..." se o
#    app do LM Studio não estiver aberto (e `open -a` não funciona a partir de shells
#    sandboxed). Por isso: tenta abrir o app, espera com timeout, e falha com instrução
#    clara em vez de travar. Solução definitiva: habilitar o serviço headless na GUI
#    (Settings → Developer → "Enable Local LLM Service" / "Run on login").
server_up() { curl -sf --max-time 2 "http://localhost:${PORT}/v1/models" >/dev/null 2>&1; }

if ! server_up; then
    if ! pgrep -q -f "LM Studio.app/Contents/MacOS"; then
        echo "app do LM Studio não está rodando — tentando abrir..."
        open -a "LM Studio" 2>/dev/null || true
        n=0; while ! pgrep -q -f "LM Studio.app/Contents/MacOS" && [ $n -lt 20 ]; do sleep 1; n=$((n+1)); done
        if ! pgrep -q -f "LM Studio.app/Contents/MacOS"; then
            echo "erro: não consegui abrir o LM Studio a partir daqui." >&2
            echo "      Abra o app manualmente (Spotlight → LM Studio) e rode bin/serve.sh de novo." >&2
            echo "      Para nunca mais depender disso: Settings → Developer → habilite o serviço" >&2
            echo "      headless ('Enable Local LLM Service' + 'Run on login')." >&2
            exit 1
        fi
    fi
    if command -v lms >/dev/null 2>&1; then
        echo "subindo servidor na porta ${PORT}..."
        lms server start --port "$PORT" >/dev/null 2>&1 &
        LMS_PID=$!
        n=0; while ! server_up && [ $n -lt 45 ]; do sleep 1; n=$((n+1)); done
        kill "$LMS_PID" 2>/dev/null || true
    fi
    if ! server_up; then
        echo "erro: servidor não respondeu em localhost:${PORT} após 45s." >&2
        echo "      No LM Studio: Developer → Start Server (porta ${PORT})." >&2
        exit 1
    fi
fi

# 3. Modelos residentes — PERFIS DE MEMÓRIA (incidente 06/09/2026: 72 GB em 48 GB de RAM)
#    dev (padrão):   só BGE-M3 explícito. O Qwen NÃO é carregado aqui: fica por conta do JIT
#                    do LM Studio, que descarrega a variante anterior ao trocar (Auto-Evict só
#                    vale para modelos JIT — carregar explicitamente quebra a troca e soma 16 GB
#                    por variante). Orçamento: 16 GB (1 Qwen) + KV + 0,6 GB.
#    atendimento:    bin/serve.sh --atendimento → também carrega o Gemma (15,6 GB). Não combinar
#                    com sessões longas de desenvolvimento: 2 Qwen + Gemma não cabem.
PROFILE="dev"; [ "${1:-}" = "--atendimento" ] && PROFILE="atendimento"
is_loaded() {
    curl -sf --max-time 3 "http://localhost:${PORT}/api/v0/models" \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); ms=d.get("data",d); sys.exit(0 if any(m.get("id")==sys.argv[1] and m.get("state")=="loaded" for m in ms) else 1)' "$1" 2>/dev/null
}
load_once() {  # $1 = modelo, $2... = flags extras do lms load
    m="$1"; shift
    if is_loaded "$m"; then echo "já carregado: $m"; return 0; fi
    out=$(lms load "$m" "$@" 2>&1 | tr '\r' '\n' | grep -E "loaded successfully|identifier|rror" | tail -2) || true
    echo "${out:-aviso: falha ao carregar $m}"
}
if command -v lms >/dev/null 2>&1; then
    load_once "$EMBEDDINGS"
    if [ "$PROFILE" = "atendimento" ]; then
        load_once "$ATENDIMENTO"
    else
        # garante que o Gemma não ficou residente de uma sessão anterior
        is_loaded "$ATENDIMENTO" && { echo "perfil dev: descarregando $ATENDIMENTO"; lms unload "$ATENDIMENTO" >/dev/null 2>&1 || true; }
    fi
    # nunca mais de uma variante do Qwen residente
    loaded_qwen=$(curl -sf --max-time 3 "http://localhost:${PORT}/api/v0/models" | python3 -c 'import json,sys; d=json.load(sys.stdin); ms=d.get("data",d); print(" ".join(m["id"] for m in ms if m.get("state")=="loaded" and m["id"].startswith("qwen3.8-27b")))' 2>/dev/null || true)
    set -- $loaded_qwen; if [ $# -gt 1 ]; then shift; for extra in "$@"; do echo "duas variantes do Qwen residentes — descarregando $extra"; lms unload "$extra" >/dev/null 2>&1 || true; done; fi
fi
echo "perfil: $PROFILE"
if [ "$PROFILE" = "atendimento" ]; then touch /tmp/local-llm-atendimento.on; else rm -f /tmp/local-llm-atendimento.on; fi

echo "modelos CARREGADOS (lms ps):"
lms ps 2>/dev/null | awk 'NR>2 && NF{print " -", $1, $4, $5}' || true


# 3a. Roteador (localhost:4000) — deve estar de pé via LaunchAgent (launchd/com.local-llm.router.plist).
#     É ele que a extensão do VS Code usa; se cair, TODA sessão do Claude falha (nuvem inclusive).
if curl -sf --max-time 2 -H "x-api-key: x" "http://localhost:4000/v1/models" >/dev/null 2>&1; then
    echo "roteador OK em localhost:4000 (/model qwen3.8-27b-* → executor via JIT, claude-* → nuvem)"
else
    echo "aviso: roteador FORA em localhost:4000 — a extensão do VS Code vai falhar."
    echo "       Recarregue: launchctl kickstart -k gui/$(id -u)/com.local-llm.router"
fi

# 3b. Warmup: a 1ª inferência pós-load paga ~27s de compilação Metal — pagar agora,
#     não na frente do cliente.
[ "$PROFILE" = "atendimento" ] && {
echo "warmup do modelo de atendimento..."
curl -sf --max-time 90 "http://localhost:${PORT}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${ATENDIMENTO}\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" \
    >/dev/null && echo "warmup OK" || echo "aviso: warmup falhou"
}

# 4. Máquina acordada enquanto o serviço estiver de pé
#    -d display, -i idle, -m disco, -s sistema (na tomada)
echo "segurando a máquina acordada (Ctrl+C encerra)..."
exec caffeinate -dims
