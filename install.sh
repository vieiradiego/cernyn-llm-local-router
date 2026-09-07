#!/bin/sh
# cernyn-llm-local-router — instala a stack nesta máquina (macOS, Apple Silicon). Idempotente.
#   --dry-run   só mostra o que faria
# Pré-requisitos: LM Studio instalado e aberto pelo menos uma vez; Claude Code (CLI ou extensão).
set -eu
REPO=$(cd "$(dirname "$0")" && pwd); DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
run() { if [ $DRY = 1 ]; then echo "  [dry-run] $*"; else eval "$*"; fi; }
gen() { sed "s|__REPO__|$REPO|g; s|__HOME__|$HOME|g" "$1" > "$2"; echo "  gerado: $2"; }
echo "== 1. arquivos gerados a partir de templates =="
mkdir -p "$REPO/launchd"
for f in router memguard healthcheck; do gen "$REPO/templates/com.local-llm.$f.plist.tpl" "$REPO/launchd/com.local-llm.$f.plist"; done
gen "$REPO/templates/mcp.json.tpl" "$REPO/.mcp.json"
echo "== 2. ambiente Python dos MCPs =="
[ -x "$REPO/mcp/.venv/bin/python" ] || run "python3 -m venv '$REPO/mcp/.venv' && '$REPO/mcp/.venv/bin/pip' install -q -r '$REPO/mcp/requirements.txt'"
echo "== 3. MCPs no escopo do usuário do Claude Code =="
if command -v claude >/dev/null 2>&1; then
    run "claude mcp remove -s user knowledge >/dev/null 2>&1 || true; claude mcp add -s user knowledge -- '$REPO/mcp/.venv/bin/python' '$REPO/mcp/server.py' >/dev/null"
    run "claude mcp remove -s user web >/dev/null 2>&1 || true; claude mcp add -s user web -- '$REPO/mcp/.venv/bin/python' '$REPO/mcp/web_server.py' >/dev/null"
else echo "  aviso: 'claude' não está no PATH — registre os MCPs depois (README)"; fi
echo "== 4. LaunchAgents: roteador (obrigatório) e guarda de memória =="
for f in router memguard; do
    run "cp '$REPO/launchd/com.local-llm.$f.plist' '$HOME/Library/LaunchAgents/' && launchctl bootout gui/\$(id -u)/com.local-llm.$f 2>/dev/null; launchctl bootstrap gui/\$(id -u) '$HOME/Library/LaunchAgents/com.local-llm.$f.plist'"
done
echo "== 5. VS Code: aponte a extensão Claude Code para o roteador (user settings) =="
echo '  "claudeCode.environmentVariables": [{ "name": "ANTHROPIC_BASE_URL", "value": "http://localhost:4000" }]'
echo "  depois: Developer: Reload Window. Variantes do Qwen: veja docs/02-configuracao.md."
echo "== pronto. verificar: curl -s -o /dev/null -w '%{http_code}\\n' -H 'x-api-key: x' localhost:4000/v1/models =="
