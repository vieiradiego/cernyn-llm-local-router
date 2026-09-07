<?xml version="1.0" encoding="UTF-8"?>
<!-- Healthcheck do bot a cada 60s. NÃO instalado automaticamente (decisão sua):
     instalar:  cp launchd/com.local-llm.healthcheck.plist ~/Library/LaunchAgents/ \
                && launchctl load ~/Library/LaunchAgents/com.local-llm.healthcheck.plist
     remover:   launchctl unload ~/Library/LaunchAgents/com.local-llm.healthcheck.plist -->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.local-llm.healthcheck</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>__REPO__/bin/healthcheck.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>__HOME__/.lmstudio/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
    <key>StartInterval</key><integer>60</integer>
    <key>StandardErrorPath</key><string>/tmp/local-llm-healthcheck.log</string>
</dict>
</plist>
