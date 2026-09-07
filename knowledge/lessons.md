# Lições pós-tarefa

Uma entrada por tarefa executada pelo modelo local. Preencher no portão de revisão
(passo 3 do fluxo de realimentação, ver README). Quando um mesmo tipo de lição se
repetir, promovê-la a `conventions/<projeto>.md` — lá ela entra no CLAUDE.md do
repo-alvo e no bloco "Convenções aplicáveis" dos planos.

Formato:

## AAAA-MM-DD — <tarefa> (<projeto>)
- **O que a revisão pegou**: <violação, convenção ignorada, padrão bom a repetir>
- **Regra extraída**: <a regra em uma frase imperativa, verificável>
- **Promovida a convenção?** não | sim → conventions/<projeto>.md

---

## 2026-09-07 — LUM-128 × nothink, 1ª tentativa (repo-alvo, run inválido)
- **O que a revisão pegou**: o executor local recebeu 32× "This command requires approval" para
  o mesmo `npm install --save-dev …` e repetiu o comando idêntico até o cap de 60 turnos, sem
  trocar de estratégia nem reportar o bloqueio. A configuração do ESLint que ele escreveu
  estava correta; só faltava a dependência.
- **Regra extraída**: (harness) a allowlist do executor deve cobrir tudo que o plano exige
  (`npm install` quando o plano adiciona dependência). (modelo) O Qwen sem raciocínio não
  reconhece negação de permissão como sinal para mudar de abordagem — um detector de
  não-convergência (N chamadas idênticas consecutivas → abortar) evitaria 13 min perdidos.
- **Promovida a convenção?** não (lição de harness, registrada em docs/04 D14 e no runbook)

## 2026-09-07 — LUM-128 × nothink e × low, runs válidos (repo-alvo)
- **O que a revisão pegou**: os dois regimes responderam ao `ERESOLVE` (peer do
  eslint-plugin-jsx-a11y vs ESLint 10) com `npm install --legacy-peer-deps`, que removeu o
  `vite` (peer do vitest) do lock e quebrou `npm run test`. Nenhum escreveu o `lefthook.yml`
  (só ficou o exemplo gerado pelo `lefthook install`) nem o script `prepare`.
- **Regra extraída**: nunca `--legacy-peer-deps` neste repo; diante de ERESOLVE, fixar a
  versão compatível ou usar `--force` e conferir `git diff package-lock.json` por remoções.
  Planos que introduzem ferramenta nova devem trazer o snippet de config final, não só o nome.
- **Promovida a convenção?** sim → conventions/<repo-alvo>.md (a criar no repo-alvo)
