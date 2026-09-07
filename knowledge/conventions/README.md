# Convenções por projeto

Um arquivo por repo-alvo (`<projeto>.md`), com regras imperativas e verificáveis que o
executor local deve seguir SEMPRE. Fonte: sessões de planejamento/revisão com Fable/Opus
e lições recorrentes de `../lessons.md`.

Regras de escrita (o executor local segue melhor quando):
- imperativa e curta: "Use X", "Nunca Y" — não "prefira considerar";
- verificável no diff: dá para conferir com grep ou olho no code review;
- com o porquê em uma linha — modelos aderem mais quando a razão está junto;
- máx. ~30 regras por projeto — acima disso o modelo dilui a atenção; podar.

Uso: o CLAUDE.md de cada repo-alvo incorpora (ou referencia) o arquivo do projeto, e
todo plano em docs/plans/ abre com o bloco "Convenções aplicáveis" copiado daqui.
