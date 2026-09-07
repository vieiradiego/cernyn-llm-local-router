#!/usr/bin/env python3
"""knowledge-server — MCP (stdio) de retrieval sobre o índice de conhecimento.

Tools:
  search_knowledge(query, k) — busca vetorial (cosseno, BGE-M3 via LM Studio)
  list_knowledge()           — inventário do que está indexado

Requer knowledge/.index.db gerado por mcp/index.py.
"""

import json
import os
import sqlite3
import struct
import urllib.request

import numpy as np
from mcp.server.mcpserver import MCPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "knowledge", ".index.db")
EMBED_URL = os.environ.get("EMBED_URL", "http://localhost:1234/v1/embeddings")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "text-embedding-bge-m3")
MIN_SCORE = 0.35  # abaixo disso o chunk é ruído, não resposta

mcp = MCPServer("knowledge")


def _embed(text: str) -> np.ndarray:
    req = urllib.request.Request(
        EMBED_URL,
        data=json.dumps({"model": EMBED_MODEL, "input": text}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        v = json.load(r)["data"][0]["embedding"]
    a = np.asarray(v, dtype=np.float32)
    return a / (np.linalg.norm(a) or 1.0)


def _load_index():
    con = sqlite3.connect(DB)
    rows = con.execute("SELECT path, section, text, vec FROM chunks").fetchall()
    con.close()
    if not rows:
        return [], np.zeros((0, 1))
    mat = np.vstack(
        [np.asarray(struct.unpack(f"{len(v) // 4}f", v), dtype=np.float32) for *_, v in rows]
    )
    mat /= np.linalg.norm(mat, axis=1, keepdims=True).clip(min=1e-9)
    return [(p, s, t) for p, s, t, _ in rows], mat


@mcp.tool()
def search_knowledge(query: str, k: int = 5) -> str:
    """Busca convenções, lições, ADRs e planos anteriores relevantes à query.
    Use ANTES de implementar, para saber como este projeto faz as coisas.
    Retorna trechos com a fonte (arquivo#seção)."""
    if not os.path.exists(DB):
        return "Índice não existe. Rode: python3 mcp/index.py"
    meta, mat = _load_index()
    if not meta:
        return "Índice vazio — nada indexado ainda."
    scores = mat @ _embed(query)
    order = np.argsort(-scores)[: max(1, min(k, 10))]
    hits = [
        f"[{scores[i]:.2f}] {meta[i][0]}#{meta[i][1]}\n{meta[i][2]}"
        for i in order
        if scores[i] >= MIN_SCORE
    ]
    return "\n\n---\n\n".join(hits) if hits else "Nada relevante no índice para essa query."


@mcp.tool()
def list_knowledge() -> str:
    """Lista o que o índice de conhecimento contém (arquivos e nº de trechos)."""
    if not os.path.exists(DB):
        return "Índice não existe. Rode: python3 mcp/index.py"
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT path, COUNT(*) FROM chunks GROUP BY path ORDER BY path"
    ).fetchall()
    con.close()
    return "\n".join(f"{p} ({n} trechos)" for p, n in rows) or "Índice vazio."


if __name__ == "__main__":
    mcp.run()
