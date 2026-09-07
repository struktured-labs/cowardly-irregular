#!/usr/bin/env bash
# Build all "The Calibrant" book artifacts from current novella source.
#
# Pipeline:
#   1. make_epub.py  -> 3 EPUBs (novellas, alternates, short_stories) via ebooklib
#   2. pandoc+weasyprint -> the_calibrant_novellas.pdf (preserves embedded BOOK_CSS)
#   3. pandoc -> the_calibrant_novellas.md / .txt (combined single-file exports)
#
# weasyprint is the PDF engine on purpose: the book styling is HTML/CSS
# (serif body, centered chapter titles, green terminal code blocks, page
# breaks). pdflatex would discard all of it.
#
# Requires: uv, pandoc, weasyprint (all already on this machine).
# Run from anywhere; paths are resolved relative to the repo root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOVELLAS="$REPO_ROOT/docs/novellas"
EPUB="$NOVELLAS/the_calibrant_novellas.epub"

echo "[1/3] Rebuilding EPUBs from source novellas..."
uv run --with ebooklib python "$REPO_ROOT/tools/make_epub.py"

echo "[2/3] Building PDF (weasyprint, preserves book CSS)..."
pandoc "$EPUB" -o "$NOVELLAS/the_calibrant_novellas.pdf" --pdf-engine=weasyprint

echo "[3/3] Building combined .md and .txt exports..."
pandoc "$EPUB" -t markdown -o "$NOVELLAS/the_calibrant_novellas.md"
pandoc "$EPUB" -t plain    -o "$NOVELLAS/the_calibrant_novellas.txt"

echo "Done. Artifacts in $NOVELLAS:"
ls -la --time-style=+%Y-%m-%d_%H:%M "$NOVELLAS"/the_calibrant_novellas.{epub,pdf,md,txt}
