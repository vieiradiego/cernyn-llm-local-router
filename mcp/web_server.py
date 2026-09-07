#!/usr/bin/env python3
"""web — MCP (stdio) de acesso à internet para o modelo LOCAL.

Por que existe: a WebSearch do Claude Code depende da API da Anthropic e não funciona quando o
modelo selecionado é local (medido 06/09/2026). Este servidor dá busca sem chave (DuckDuckGo)
e leitura de página (trafilatura → texto limpo), tudo client-side.

Tools:
  search_web(query, k=5)          → títulos, URLs e resumos
  fetch_page(url, max_chars=8000) → texto principal da página
"""
import logging
import sys

import httpx
import trafilatura

# MCP stdio usa stdout para o protocolo: qualquer log das libs vai para stderr, e só avisos.
logging.basicConfig(stream=sys.stderr, level=logging.WARNING)
for _n in ("httpx", "httpcore", "ddgs", "trafilatura", "primp"):
    logging.getLogger(_n).setLevel(logging.WARNING)
from ddgs import DDGS
from mcp.server.mcpserver import MCPServer

mcp = MCPServer("web")
UA = "Mozilla/5.0 (Macintosh) local-llm-web/1.0"


@mcp.tool()
def search_web(query: str, k: int = 5) -> str:
    """Busca na web (DuckDuckGo, sem chave). Retorna até k resultados com título, URL e resumo.
    Use para encontrar documentação, changelogs, issues e exemplos atuais."""
    try:
        rows = list(DDGS().text(query, max_results=max(1, min(k, 10))))
    except Exception as e:
        return f"busca falhou: {e}"
    if not rows:
        return "nenhum resultado."
    return "\n\n".join(f"[{i+1}] {r.get('title','')}\n{r.get('href','')}\n{r.get('body','')}" for i, r in enumerate(rows))


MAX_BODY = 2_000_000  # bytes


def _assert_public(url: str) -> None:
    import ipaddress, socket
    from urllib.parse import urlparse
    u = urlparse(url)
    if u.scheme not in ("http", "https") or not u.hostname:
        raise ValueError(f"URL recusada (esquema/host): {url}")
    host = u.hostname
    if host == "localhost" or host.endswith(".local") or host.endswith(".internal"):
        raise ValueError(f"host interno recusado: {host}")
    for info in socket.getaddrinfo(host, None):
        ip = ipaddress.ip_address(info[4][0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast or ip.is_unspecified:
            raise ValueError(f"endereço não público recusado: {host} → {ip}")


def _fetch_public(url: str, hops: int = 5) -> httpx.Response:
    """GET com validação anti-SSRF a cada redirect e teto de tamanho do corpo."""
    for _ in range(hops):
        _assert_public(url)
        with httpx.stream("GET", url, headers={"User-Agent": UA}, follow_redirects=False, timeout=20) as r:
            if r.is_redirect and r.headers.get("location"):
                url = str(r.url.join(r.headers["location"]))
                continue
            r.raise_for_status()
            chunks, size = [], 0
            for c in r.iter_bytes():
                size += len(c)
                if size > MAX_BODY:
                    raise ValueError(f"corpo maior que {MAX_BODY} bytes")
                chunks.append(c)
            r._content = b"".join(chunks)  # noqa: SLF001 — materializa para r.text
            return r
    raise ValueError("redirects demais")


@mcp.tool()
def fetch_page(url: str, max_chars: int = 8000) -> str:
    """Baixa uma URL e devolve o texto principal (sem menus/anúncios), cortado em max_chars.
    Use depois de search_web para ler a fonte de verdade."""
    # Anti-SSRF: só http/https, nunca loopback/rede privada/link-local (uma página lida poderia
    # instruir o modelo a ler serviços internos); redirects são revalidados um a um; corpo com teto.
    try:
        r = _fetch_public(url)
    except Exception as e:
        return f"fetch falhou: {e}"
    ctype = r.headers.get("content-type", "")
    if ctype and not any(t in ctype for t in ("text/", "html", "xml", "json")):
        return f"fetch ignorado: conteúdo {ctype.split(';')[0]} não é texto."
    text = trafilatura.extract(r.text, include_links=False, include_tables=True, url=url) or ""
    if not text.strip():  # fallback bruto
        text = trafilatura.html2txt(r.text) or r.text
    text = text.strip()
    cut = max(500, min(max_chars, 50000))
    return text[:cut] + (f"\n\n[... truncado em {cut} chars de {len(text)}]" if len(text) > cut else "")


if __name__ == "__main__":
    mcp.run()
