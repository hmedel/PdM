#!/usr/bin/env bash
# Renderiza un whitepaper markdown a PDF maquetado (pandoc + xelatex).
#
# Maneja dos problemas del Markdown técnico:
#   1) Mezcla de '$' literales (montos en dólares) con matemática LaTeX ($...$, $$...$$):
#      escapa los '$' que preceden a un dígito para que pandoc no los lea como math.
#   2) Símbolos Unicode (→ ÷ ≈ × · −, ¢) que dan "tofu" en xelatex/Latin Modern:
#      los mueve a modo math (siempre renderiza) o a texto ASCII.
# Además activa autolink_bare_uris + xurl para que las URLs largas rompan dentro del margen.
#
# Uso:  scripts/render_pdf.sh docs/EconomicCase_PdM_Whitepaper.md [docs/salida.pdf]
# Requiere: pandoc, xelatex (MacTeX/TeX Live), perl, awk.
set -euo pipefail

SRC="${1:?Falta el .md de entrada}"
OUT="${2:-${SRC%.md}.pdf}"
WORK="$(mktemp -t wp_render.XXXX.md)"
trap 'rm -f "$WORK"' EXIT

# Metadatos de portada (título/subtítulo se toman del H1/H3 del documento).
TITLE="$(grep -m1 '^# '   "$SRC" | sed 's/^# //')"
SUBTITLE="$(grep -m1 '^### ' "$SRC" | sed 's/^### //')"

{
  printf '%s\n' '---'
  printf 'title: "%s"\n'    "$TITLE"
  printf 'subtitle: "%s"\n' "$SUBTITLE"
  printf '%s\n' 'author: "PhAIMaT — Tracker / Predictive Maintenance (PdM)"'
  printf '%s\n' 'date: "June 2026"'
  printf '%s\n\n' '---'

  # Cuerpo: desde el primer "## " (deja fuera el título/subtítulo/regla iniciales).
  awk '/^## /{p=1} p' "$SRC" \
  | perl -CSD -pe '
      s/\$(?=\d)/\\\$/g;                 # escapa $ de montos (antes de dígito)
      s/\x{00A2}\/mi/cents\/mi/g;        # ¢/mi -> cents/mi
      s/\x{00A2}/cents/g;                # ¢    -> cents
      s/\x{2212}/-/g;                    # − (U+2212) -> guión ASCII
      s/\x{2192}/\$\\to\$/g;             # →
      s/\x{00F7}/\$\\div\$/g;            # ÷
      s/\x{2248}/\$\\approx\$/g;         # ≈
      s/\x{00D7}/\$\\times\$/g;          # ×
      s/\x{00B7}/\$\\cdot\$/g;           # ·
    '
} > "$WORK"

# Las imágenes se referencian relativas al .md (p.ej. ../figures/x.png); resource-path al dir del .md.
SRCDIR="$(cd "$(dirname "$SRC")" && pwd)"

pandoc "$WORK" -f markdown+autolink_bare_uris -o "$OUT" \
  --pdf-engine=xelatex \
  --resource-path="$SRCDIR" \
  -V lang="${PDFLANG:-es}" \
  --toc --toc-depth=2 \
  -V geometry:margin=1in \
  -V fontsize=11pt \
  -V colorlinks=true -V linkcolor=blue -V urlcolor=blue -V toccolor=black \
  -V documentclass=article \
  -V header-includes='\usepackage{xurl}'

echo "OK -> $OUT"
