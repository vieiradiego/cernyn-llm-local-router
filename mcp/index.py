#!/usr/bin/env python3
"""Indexador do knowledge-server.

Varre knowledge/ e docs/plans/ (+ diretórios extras via KNOWLEDGE_EXTRA_DIRS,
separados por ':'), divide os .md por seção, gera embeddings via LM Studio
(text-embedding-bge-m3) e grava em knowledge/.index.db (SQLite; vetores como
BLOB float32 — a busca por cosseno é feita em numpy no server).

Incremental: arquivo inalterado (mtime+sha1) não é reprocessado.

Uso: python3 mcp/index.py [--rebuild]
"""

import hashlib
import json
import os
import sqlite3
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "knowledge", ".index.db")
EMBED_URL = os.environ.get("EMBED_URL", "http://localhost:1234/v1/embeddings")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "text-embedding-bge-m3")
MAX_CHUNK_CHARS = 2000  # ~500 tokens
SOURCES = [os.path.join(ROOT, "knowledge"), os.path.join(ROOT, "docs", "plans")]
SOURCES += [d for d in os.environ.get("KNOWLEDGE_EXTRA_DIRS", "").split(":") if d]


def embed(texts: list[str]) -> list[list[float]]:
    req = urllib.request.Request(
        EMBED_URL,
        data=json.dumps({"model": EMBED_MODEL, "input": texts}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        data = json.load(r)["data"]
    return [d["embedding"] for d in sorted(data, key=lambda d: d["index"])]


def chunk_markdown(text: str) -> list[tuple[str, str]]:
    """Divide por headings; funde seções pequenas; corta as grandes. -> [(seção, corpo)]"""
    sections: list[tuple[str, list[str]]] = [("(início)", [])]
    for line in text.splitlines():
        if line.startswith("#"):
            sections.append((line.lstrip("# ").strip() or "(sem título)", [line]))
        else:
            sections[-1][1].append(line)
    chunks = []
    for title, lines in sections:
        body = "\n".join(lines).strip()
        if not body:
            continue
        while len(body) > MAX_CHUNK_CHARS:  # corta em parágrafo mais próximo
            cut = body.rfind("\n\n", 0, MAX_CHUNK_CHARS)
            cut = cut if cut > 200 else MAX_CHUNK_CHARS
            chunks.append((title, body[:cut].strip()))
            body = body[cut:].strip()
        chunks.append((title, body))
    # funde vizinhos minúsculos para não poluir o índice
    merged: list[tuple[str, str]] = []
    for title, body in chunks:
        if merged and len(merged[-1][1]) + len(body) < 400:
            merged[-1] = (merged[-1][0], merged[-1][1] + "\n\n" + body)
        else:
            merged.append((title, body))
    return merged


def main() -> int:
    if "--rebuild" in sys.argv and os.path.exists(DB):
        os.remove(DB)
    con = sqlite3.connect(DB)
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, mtime REAL, sha1 TEXT);
        CREATE TABLE IF NOT EXISTS chunks(
            id INTEGER PRIMARY KEY, path TEXT, section TEXT, text TEXT, vec BLOB);
        CREATE INDEX IF NOT EXISTS chunks_path ON chunks(path);
        """
    )

    seen, new_chunks, skipped = set(), 0, 0
    for src in SOURCES:
        if not os.path.isdir(src):
            continue
        for dirpath, _, files in os.walk(src):
            if ".venv" in dirpath:
                continue
            for name in sorted(files):
                if not name.endswith(".md"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT)
                seen.add(rel)
                raw = open(path, encoding="utf-8", errors="replace").read()
                sha = hashlib.sha1(raw.encode()).hexdigest()
                mtime = os.path.getmtime(path)
                row = con.execute("SELECT mtime, sha1 FROM files WHERE path=?", (rel,)).fetchone()
                if row and row[0] == mtime and row[1] == sha:
                    skipped += 1
                    continue
                con.execute("DELETE FROM chunks WHERE path=?", (rel,))
                parts = chunk_markdown(raw)
                if parts:
                    vecs = embed([f"{rel} — {t}\n{b}" for t, b in parts])
                    import struct
                    for (title, body), v in zip(parts, vecs):
                        blob = struct.pack(f"{len(v)}f", *v)
                        con.execute(
                            "INSERT INTO chunks(path, section, text, vec) VALUES(?,?,?,?)",
                            (rel, title, body, blob),
                        )
                    new_chunks += len(parts)
                con.execute(
                    "INSERT OR REPLACE INTO files(path, mtime, sha1) VALUES(?,?,?)",
                    (rel, mtime, sha),
                )
                con.commit()

    # remove arquivos que sumiram do disco
    for (path,) in con.execute("SELECT path FROM files").fetchall():
        if path not in seen:
            con.execute("DELETE FROM chunks WHERE path=?", (path,))
            con.execute("DELETE FROM files WHERE path=?", (path,))
    con.commit()

    total = con.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    nfiles = con.execute("SELECT COUNT(*) FROM files").fetchone()[0]
    print(f"indexados: {nfiles} arquivos, {total} chunks ({new_chunks} novos, {skipped} inalterados)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
