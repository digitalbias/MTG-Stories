#!/usr/bin/env bash
#
# build_complete_epub.sh — build a single EPUB (no images) combining every
# story from every set, from COMPLETE_STORIES.typ.
#
# Same Typst HTML export -> pandoc pipeline as build_set.sh's build_epub,
# with one extra step: COMPLETE_STORIES.typ prepends its own title page and
# a Typst-generated `#outline` table of contents (a <nav role="doc-toc">
# full of #loc-N anchor links). Once pandoc splits the HTML into per-story
# chapter files those anchors no longer resolve, so that nav block is
# stripped entirely -- pandoc's own --toc (over the story-title headings)
# replaces it.
#
# Output: COMPLETE_STORIES_WITHOUT_IMAGES.epub and
# COMPLETE_STORIES_WITHOUT_IMAGES.pdf (repo root, gitignored -- too big for
# GitHub).

set -euo pipefail

cd "$(dirname "$0")"

WRAPPER="COMPLETE_STORIES.typ"
OUT="COMPLETE_STORIES_WITHOUT_IMAGES.epub"
TITLE="Magic 2013 through Reality Fracture"
HTML_TMP="COMPLETE_STORIES_epub_tmp.html"
HTML_SHRUNK="COMPLETE_STORIES_epub_tmp_shrunk.html"

typst compile --root . --input with_images=false "$WRAPPER" "${OUT%.epub}.pdf"
echo "  compiled ${OUT%.epub}.pdf"

typst compile --root . --features html --format html \
    --input with_images=false "$WRAPPER" "$HTML_TMP"
echo "  exported $HTML_TMP"

python3 "$(dirname "$0")/shrink_html_images.py" "$HTML_TMP" "$HTML_SHRUNK"

perl -0777 -pe 's/<nav role="doc-toc">.*?<\/nav>//s' -i "$HTML_SHRUNK"
perl -0777 -pe 's/<h2>.*?<\/h2>//s' -i "$HTML_SHRUNK"

pandoc "$HTML_SHRUNK" -o "$OUT" \
    --split-level=3 --toc --toc-depth=3 \
    --metadata title="$TITLE" --metadata author="Wizards of the Coast"

rm -f "$HTML_TMP" "$HTML_SHRUNK"
echo "  compiled $OUT"
