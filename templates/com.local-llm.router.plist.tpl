<?xml version="1.0" encoding="UTF-8"?>
<!-- Roteador Anthropic-API (localhost:4000): claude-* → nuvem, resto → LM Studio.
     Precisa estar SEMPRE de pé quando a extensão aponta ANTHROPIC_BASE_URL para ele.
     remover:  launchctl bootout gui/$(id -u)/com.local-llm.router
               && rm ~/Library/LaunchAgents/com.local-llm.router.plist -->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.local-llm.router</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>__REPO__/router/router.py</string>
        <string>4000</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <!-- Opção C (decisão do usuário): no caminho LOCAL, remover as tools dos connectors
             claude.ai (mcp__claude_ai_*), que somam ~100K tokens e não cabem no Qwen.
             Nuvem intacta. Para desligar: apagar esta chave e recarregar o agent. -->
        <key>ROUTER_SANITIZE_LOCAL</key><string>1</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/tmp/local-llm-router.log</string>
    <key>StandardErrorPath</key><string>/tmp/local-llm-router.log</string>
</dict>
</plist>
