#!/usr/bin/env python3
"""Roteador Anthropic-API local: um único endpoint para o Claude Code, dois destinos.

  model começa com "claude"  → https://api.anthropic.com  (headers repassados intactos,
                               inclusive o Authorization do login claude.ai)
  qualquer outro model       → LM Studio em http://localhost:1234 (qwen3.8-27b etc.)

Assim `/model qwen3.8-27b` e `/model claude-fable-5-1` funcionam NA MESMA sessão da
extensão, sem trocar de janela. Streaming (SSE) repassado byte a byte.

Uso: python3 router/router.py [porta=4000]
"""
import http.client
import json
import os
import sys
import time
import urllib.request as urllib_request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

# upstreams (sobrescrevíveis por env — usado pelo tests/smoke.sh com servidores falsos)
CLOUD = (os.environ.get("ROUTER_CLOUD_HOST", "api.anthropic.com"), int(os.environ.get("ROUTER_CLOUD_PORT", "443")), os.environ.get("ROUTER_CLOUD_TLS", "1") == "1")
LOCAL = (os.environ.get("ROUTER_LOCAL_HOST", "localhost"), int(os.environ.get("ROUTER_LOCAL_PORT", "1234")), False)
HOP = {"host", "content-length", "connection", "transfer-encoding", "keep-alive", "accept-encoding"}
CREDENTIAL_HEADERS = {"authorization", "x-api-key", "cookie"}


# Nomes de modelo = identificadores do LM Studio (`lms ps`): /model qwen3.8-27b, /model
# gemma-4-26b-a4b-it-qat. Sem aliases por padrão, para o nome na extensão ser sempre o mesmo
# do servidor. Opcional: ROUTER_ALIASES="local=qwen3.8-27b,gemma=gemma-4-26b-a4b-it-qat".
ALIASES = dict(kv.split("=", 1) for kv in os.environ.get("ROUTER_ALIASES", "").split(",") if "=" in kv)


def pick(body: bytes):
    try:
        model = json.loads(body or b"{}").get("model", "")
    except Exception:
        model = ""
    # a decisão "local" é pela IDENTIDADE do destino (LOCAL), nunca por "não é TLS"
    return (CLOUD, model, False) if str(model).startswith("claude") else (LOCAL, model, True)


# --- saneamento para o destino local -------------------------------------------------
# O Claude Code manda ~80K tokens de prompt (100+ tools dos connectors claude.ai) com
# max_tokens=32000: estoura o contexto carregado. A 17 tok/s, 32K tokens seriam 30 min de
# geração — cap não custa nada. E as tools dos connectors da nuvem não fazem sentido para o
# modelo local: removê-las corta dezenas de milhares de tokens de prefill por turno.
# Por padrão o roteador é TRANSPARENTE: o usuário escolhe o modelo e recebe o comportamento
# daquele modelo. Os ajustes abaixo só entram com ROUTER_SANITIZE_LOCAL=1 (diagnóstico).
SANITIZE = os.environ.get("ROUTER_SANITIZE_LOCAL", "0") == "1"
AUTO_SWAP = os.environ.get("ROUTER_AUTO_SWAP", "0") == "1"
LOCAL_MAX_TOKENS = int(os.environ.get("ROUTER_LOCAL_MAX_TOKENS", "0"))  # 0 = sem cap
STRIP_TOOL_PREFIXES = tuple(p for p in os.environ.get("ROUTER_LOCAL_STRIP_TOOLS", "mcp__claude_ai_").split(",") if p)


def sanitize_local(body: bytes) -> bytes:
    try:
        d = json.loads(body or b"{}")
    except Exception:
        return body
    if not isinstance(d, dict):
        return body
    if d.get("model") in ALIASES:
        d["model"] = ALIASES[d["model"]]
    if LOCAL_MAX_TOKENS and isinstance(d.get("max_tokens"), int) and d["max_tokens"] > LOCAL_MAX_TOKENS:
        d["max_tokens"] = LOCAL_MAX_TOKENS
    if STRIP_TOOL_PREFIXES and isinstance(d.get("tools"), list):
        d["tools"] = [t for t in d["tools"] if not str(t.get("name", "")).startswith(STRIP_TOOL_PREFIXES)]
    return json.dumps(d).encode()


# --- troca automática de variante do executor ----------------------------------------
# qwen3.8-27b / -low / -nothink são o MESMO peso com templates diferentes; só uma cabe na
# memória junto do Gemma. Se a extensão pedir uma variante não carregada, descarregamos a
# irmã e carregamos a pedida (~6s, pesos em page cache). LMS = CLI do LM Studio.
import subprocess
LMS = os.path.expanduser("~/.lmstudio/bin/lms")
SWAP_FAMILY = os.environ.get("ROUTER_SWAP_FAMILY", "qwen3.8-27b")  # prefixo das variantes
_swap_lock = __import__("threading").Lock()


def loaded_models():
    """Só os CARREGADOS. /v1/models lista todos os baixados; o estado vem do /api/v0/models."""
    try:
        with urllib_request.urlopen(f"http://{LOCAL[0]}:{LOCAL[1]}/api/v0/models", timeout=5) as r:
            d = json.load(r)
        ms = d.get("data", d) if isinstance(d, dict) else d
        return {m["id"] for m in ms if m.get("state") == "loaded" or m.get("loaded") is True}
    except Exception:
        out = subprocess.run([LMS, "ps"], capture_output=True, text=True, timeout=30).stdout
        return {ln.split()[0] for ln in out.splitlines()[2:] if ln.strip()}


def ensure_loaded(model: str, log):
    if not model or not model.startswith(SWAP_FAMILY) or not os.path.exists(LMS):
        return
    with _swap_lock:
        loaded = loaded_models()
        if model in loaded:
            return
        for sib in [m for m in loaded if m.startswith(SWAP_FAMILY)]:
            log("swap: descarregando %s", sib)
            subprocess.run([LMS, "unload", sib], capture_output=True, timeout=120)
        log("swap: carregando %s", model)
        subprocess.run([LMS, "load", model, "--ttl", "3600"], capture_output=True, timeout=300)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"  # fecha a conexão no fim → streaming sem Content-Length

    def log_message(self, fmt, *a):  # log curto: destino + modelo + status
        sys.stderr.write("%s\n" % (fmt % a))

    def _proxy(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        (host, port, tls), model, is_local = pick(body)
        dump = os.environ.get("ROUTER_DUMP")  # debug: salva o corpo das requisições locais
        if dump and is_local and body:
            os.makedirs(dump, exist_ok=True)
            open(os.path.join(dump, f"{int(time.time()*1000)}.json"), "wb").write(body)
        hdrs = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        if is_local:
            # credenciais do claude.ai nunca vão para o destino local (LM Studio não as usa; com
            # ROUTER_LOCAL_HOST remoto sairiam em HTTP puro)
            for k in [k for k in hdrs if k.lower() in CREDENTIAL_HEADERS]:
                del hdrs[k]
            self.log_message("local: payload %d bytes (≈%dK tokens) [%s]", len(body), len(body) // 4000, model)
            if SANITIZE:  # opção C (decisão do usuário, 06/09/2026): remove SÓ as tools mcp__claude_ai_*
                body = sanitize_local(body)  # (cap de max_tokens só se ROUTER_LOCAL_MAX_TOKENS>0)
                self.log_message("local: sem tools dos connectors → %d bytes (≈%dK tokens)", len(body), len(body) // 4000)
            if AUTO_SWAP:  # opt-in: troca de variante pelo roteador (padrão: o LM Studio faz via JIT + Auto-Evict)
                try:
                    ensure_loaded(json.loads(body).get("model", ""), self.log_message)
                except Exception as e:
                    self.log_message("swap falhou: %s", e)
        hdrs["Host"] = host
        hdrs["Accept-Encoding"] = "identity"
        conn = (http.client.HTTPSConnection if tls else http.client.HTTPConnection)(host, port, timeout=600)
        try:
            conn.request(self.command, self.path, body=body, headers=hdrs)
            resp = conn.getresponse()
            self.log_message("%s %s → %s:%s [%s] %s", self.command, self.path, host, port, resp.status, model)
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() not in HOP | {"content-encoding"}:
                    self.send_header(k, v)
            self.end_headers()
            while True:
                chunk = resp.read1(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except BrokenPipeError:  # cliente cancelou/fechou — normal, não é erro do upstream
            self.log_message("cliente desconectou (%s)", model)
            return
        except Exception as e:  # upstream fora: devolve erro no formato da API
            self.log_message("ERRO %s:%s %s", host, port, e)
            try:
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"type": "error", "error": {"type": "api_error",
                                 "message": f"router: upstream {host}:{port} indisponível ({e})"}}).encode())
            except Exception:
                pass
        finally:
            conn.close()

    do_POST = do_GET = do_DELETE = do_PUT = _proxy


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 4000
    print(f"router em http://localhost:{port} → claude-* para api.anthropic.com, resto para LM Studio :1234", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
