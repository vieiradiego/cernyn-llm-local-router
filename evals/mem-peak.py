#!/usr/bin/env python3
"""Mede o pico de memória do daemon do LM Studio durante UM prompt longo.
Uso: mcp/.venv/bin/python evals/mem-peak.py <modelo> [tokens_alvo=90000]
Amostra o phys_footprint do processo do daemon a cada 2 s antes, durante e depois."""
import json, subprocess, sys, threading, time, urllib.request
model = sys.argv[1]; alvo = int(sys.argv[2]) if len(sys.argv) > 2 else 90000
def fp():
    pid = subprocess.run("ps -axo pid,rss,comm | grep -iE 'lmstudio|lm studio|llama|mlx' | grep -v grep | sort -k2 -rn | head -1 | awk '{print $1}'", shell=True, capture_output=True, text=True).stdout.strip()
    if not pid: return 0
    for ln in subprocess.run(["footprint", "-p", pid], capture_output=True, text=True).stdout.splitlines():
        if "phys_footprint:" in ln:
            v, u = ln.split(":")[1].split(); return float(v) * (1024 if u == "GB" else 1)
    return 0
def free():
    return subprocess.run("memory_pressure -Q | awk -F': ' '/free/{print $2}'", shell=True, capture_output=True, text=True).stdout.strip()
# calibra o filler pelo contador do próprio modelo (count_tokens não existe: usa 1 requisição curta)
linha = "linha de arquivo lido pelo agente, com identificadores, caminhos e trechos de código; "
body = {"model": model, "max_tokens": 1, "messages": [{"role": "user", "content": linha * 100}]}
req = urllib.request.Request("http://localhost:1234/v1/messages", data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "anthropic-version": "2023-06-01"})
with urllib.request.urlopen(req, timeout=600) as r: t100 = json.load(r)["usage"]["input_tokens"]
por_linha = t100 / 100; n = int(alvo / por_linha)
print(f"calibração: {por_linha:.1f} tokens/linha → {n} linhas para ~{alvo} tokens | footprint em repouso: {fp()/1024:.1f} GB, livre {free()}")
samples = []; stop = False
def sampler():
    t0 = time.time()
    while not stop: samples.append((round(time.time() - t0), fp() / 1024, free())); time.sleep(2)
th = threading.Thread(target=sampler); th.start()
body["messages"] = [{"role": "user", "content": linha * n + "\nResponda apenas: ok"}]; body["max_tokens"] = 4
req = urllib.request.Request("http://localhost:1234/v1/messages", data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "anthropic-version": "2023-06-01"})
t = time.time()
try:
    with urllib.request.urlopen(req, timeout=900) as r: u = json.load(r)["usage"]; print(f"resposta em {time.time()-t:.0f}s | input_tokens={u.get('input_tokens')}")
except Exception as e: print("erro:", str(e)[:160])
time.sleep(30); stop = True; th.join()
pico = max(s[1] for s in samples); fim = samples[-1][1]
print(f"PICO: {pico:.1f} GB | repouso após: {fim:.1f} GB | livre mínimo: {min(s[2] for s in samples)}")
print("curva:", " ".join(f"{s[0]}s={s[1]:.0f}" for s in samples[::3]))
