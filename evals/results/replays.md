# Replays — resultados brutos

| tarefa | regime | duração | turnos | req/erros | check | build | e2e referência | proibidos |
|---|---|---|---|---|---|---|---|---|
| LUM-114 | low | 35m | ? | 22/2 | ✓ | ✓ | 5 failed 3 skipped 49 passed  | — | ← INVÁLIDO: memguard interrompeu o modelo 3× (engine 36 GB, livre 6%) — parallel=4
| LUM-114 | low | 50m(TO) | ? | 28/5 | ✓ | ✓ | 5 failed 3 skipped 49 passed  | — |
| LUM-114 | low/gguf | 3m | 1 | 13/11 | ✓ | ✓ | 5 failed 3 skipped 49 passed  | — |
| LUM-114 | low/gguf | 36m | 46 | 41/2 | ✓ | ✓ | 3 skipped 54 passed  | — | ← VÁLIDO: implementação completa e aceite 100% (54 passed, baseline 49/5 failed); memguard descarregou o modelo no fim (17% livre, engine 16 GB) — 0 intervenções
| LUM-114 | nothink/gguf | 15m | 44 | 40/0 | ✓ | ✓ | 3 skipped 54 passed  | — | ← VÁLIDO: 15m31s, 0 erros, aceite 100%, 0 intervenções
| LUM-114 | base/gguf | 55m | 57 | 51/0 | ✓ | ✓ | 3 skipped 54 passed  | — | ← VÁLIDO: 55m24s, 0 erros, aceite 100%
| LUM-103 | nothink/gguf | 28m | 61 | 61/0 | ✓ | ✗ | rc=1 | — | ← FALHA no build (hook client em server component); unit ref 19/19 ✓; cap de turnos
| LUM-103 | low/gguf | 68m | 61 | 62/0 | ✓ | ✓ | 1 skipped 41 passed  | — | ← VÁLIDO: aceite 100% (e2e 41/0, unit 19/19); cap cortou só a mensagem final
| LUM-111 | nothink/gguf | 23m | 53 | 47/0 | ✓ | ✓ | 60 passed  | — | ← VÁLIDO: 23m21s, e2e 60/0, 0 erros
| LUM-111 | low/gguf | 90m(TO) | ? | 35/0 | ✗ | ✓ | 27 failed 33 passed  | — | ← TIMEOUT 90 min, incompleto (27 failed); 35 req
| LUM-128 | nothink/gguf | 14m | 61 | 61/0 | ✗ | ✓ | n/a | — | ← INVÁLIDO (harness): npm install bloqueado pela allowlist; executor repetiu o mesmo comando 32× até o cap (não-convergência)
| LUM-128 | nothink/gguf | 12m | 61 | 61/0 | ✗ | ✓ | n/a | — | ← válido, incompleto: deps + ESLint ✓, 1/3 a11y, hooks ✗ (cap de turnos)
| LUM-128 | low/gguf | 55m | 61 | 61/0 | ✗ | ✓ | n/a | — | ← válido, incompleto: lint+typecheck ✓, hooks ✗; --legacy-peer-deps podou vite → test ✗
