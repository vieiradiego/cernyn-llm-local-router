<?xml version="1.0" encoding="UTF-8"?>
<!-- Guarda de memória: a cada 30 s, descarrega o Qwen se a memória livre < 15% ou o engine
     MLX > 34 GB; descarrega tudo se < 8%. Log: /tmp/local-llm-memguard.log
     remover: launchctl bootout gui/$(id -u)/com.local-llm.memguard
              && rm ~/Library/LaunchAgents/com.local-llm.memguard.plist -->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.local-llm.memguard</string>
    <key>ProgramArguments</key>
    <array><string>/bin/sh</string><string>__REPO__/bin/memguard.sh</string></array>
    <key>EnvironmentVariables</key>
    <dict><key>MEMGUARD_MIN_FREE_PCT</key><string>12</string></dict>
    <key>StartInterval</key><integer>15</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardErrorPath</key><string>/tmp/local-llm-memguard.err</string>
</dict>
</plist>
