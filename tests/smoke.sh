#!/bin/sh
# Smoke test do roteador, sem LM Studio nem Anthropic: sobe dois servidores falsos (nuvem e
# local) e um roteador em porta alternativa; verifica roteamento por nome de modelo, passagem
# de streaming (SSE) e a opção C (remoção de tools mcp__claude_ai_* só no caminho local).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); P=4400; PC=4401; PL=4402
python3 - "$PC" "$PL" > /tmp/smoke-upstreams.log 2>&1 <<'PYEOF' &
import json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
def make(name):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_POST(self):
            n = int(self.headers.get("Content-Length") or 0); body = json.loads(self.rfile.read(n) or b"{}")
            tools = [t.get("name") for t in body.get("tools", [])]
            if body.get("stream"):
                self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
                for i in range(3): self.wfile.write(f"event: chunk\ndata: {json.dumps({'upstream': name, 'i': i})}\n\n".encode()); self.wfile.flush()
                return
            out = json.dumps({"upstream": name, "model": body.get("model"), "tools": tools, "auth": self.headers.get("Authorization")}).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(out))); self.end_headers(); self.wfile.write(out)
    return H
srv = [ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), make("cloud")), ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), make("local"))]
[threading.Thread(target=s.serve_forever, daemon=True).start() for s in srv]
threading.Event().wait()
PYEOF
UP=$!
ROUTER_CLOUD_HOST=127.0.0.1 ROUTER_CLOUD_PORT=$PC ROUTER_CLOUD_TLS=0 ROUTER_LOCAL_HOST=127.0.0.1 ROUTER_LOCAL_PORT=$PL ROUTER_SANITIZE_LOCAL=1 \
  python3 "$HERE/router/router.py" $P > /tmp/smoke-router.log 2>&1 &
RT=$!; trap 'kill $UP $RT 2>/dev/null' EXIT
n=0; until nc -z 127.0.0.1 $P 2>/dev/null && nc -z 127.0.0.1 $PL 2>/dev/null; do sleep 0.2; n=$((n+1)); [ $n -gt 50 ] && { echo "FALHA: servidores não subiram"; exit 1; }; done
fail=0; check() { [ "$1" = "$2" ] && echo "  ok   $3" || { echo "  FALHA $3: esperado '$2', obtido '$1'"; fail=1; }; }
TOOLS='[{"name":"Read"},{"name":"mcp__claude_ai_Notion__search"},{"name":"mcp__knowledge__search_knowledge"}]'
r=$(curl -s localhost:$P/v1/messages -H "Authorization: Bearer tok" -H "Content-Type: application/json" -d "{\"model\":\"claude-fable-5-1\",\"tools\":$TOOLS,\"messages\":[]}")
check "$(echo "$r" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["upstream"], len(d["tools"]), d["auth"])')" "cloud 3 Bearer tok" "claude-* → nuvem, tools intactas, Authorization repassado"
r=$(curl -s localhost:$P/v1/messages -H "Content-Type: application/json" -d "{\"model\":\"qwen3.8-27b-gguf-low\",\"tools\":$TOOLS,\"messages\":[]}")
check "$(echo "$r" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["upstream"], ",".join(d["tools"]))')" "local Read,mcp__knowledge__search_knowledge" "qwen* → local, só tools mcp__claude_ai_* removidas (opção C)"
r=$(curl -sN localhost:$P/v1/messages -H "Content-Type: application/json" -d '{"model":"qwen3.8-27b","stream":true,"messages":[]}' | grep -c "^event: chunk")
check "$r" "3" "streaming SSE repassado (3 eventos)"
r=$(curl -s -o /dev/null -w '%{http_code}' localhost:$P/v1/messages -H "Content-Type: application/json" -d '{"model":"gemma-4-26b-a4b-it-qat","messages":[]}')
check "$r" "200" "outro nome não-claude → local (200)"
[ $fail = 0 ] && echo "SMOKE OK" || { echo "SMOKE FALHOU"; exit 1; }
