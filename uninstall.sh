#!/bin/sh
# Desfaz o que install.sh instalou fora do repositório (LaunchAgents e MCPs). Não apaga modelos.
set -u
for f in router memguard healthcheck; do launchctl bootout gui/$(id -u)/com.local-llm.$f 2>/dev/null; rm -f "$HOME/Library/LaunchAgents/com.local-llm.$f.plist"; done
command -v claude >/dev/null 2>&1 && { claude mcp remove -s user knowledge 2>/dev/null; claude mcp remove -s user web 2>/dev/null; }
echo "removidos: LaunchAgents com.local-llm.* e MCPs knowledge/web (escopo usuário)."
echo "falta manual: apagar 'claudeCode.environmentVariables' do user settings do VS Code."
