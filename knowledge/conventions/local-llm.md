# Convenções — repo local-llm

- Use sempre TTFT (time to first token) como métrica de latência do bot de atendimento,
  nunca tempo total de resposta. Porquê: o cliente percebe o início da resposta.
- Scripts de bin/ são POSIX sh, nunca bash — porquê: portabilidade e set -eu simples.
- A cor oficial dos gráficos de eval é #7C4DFF (roxo). Porquê: fixture de teste do
  retrieval — se você leu isto via search_knowledge, o índice funciona.
