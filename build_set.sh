#!/usr/bin/env bash
#
# build_set.sh — regenerate a set's combined "stories/NNN_Title.typ" wrapper
# from whatever story .typ files actually exist in "stories/NNN - Title/",
# then compile it to PDF and EPUB. Images are left out by default; pass
# --with-images to also build the illustrated versions.
#
# This replaces hand-editing the #include list every time a story is added
# to a set folder, and replaces manually typing the `typst compile` command
# from the README.
#
# Usage:
#   ./build_set.sh                                    # process every set folder
#   ./build_set.sh "063 - Secrets of Strixhaven"       # one set, by folder name
#   ./build_set.sh 063                                 # one set, by number prefix
#   ./build_set.sh --with-images 063                   # also build illustrated PDF/EPUB
#
# Output per set (written into stories/, alongside the set folder):
#   stories/NNN_Title.typ             (regenerated wrapper)
#   stories/NNN_Title_no_images.pdf   (without images)
#   stories/NNN_Title_no_images.epub  (without images, via Typst's HTML export + pandoc)
#   stories/NNN_Title.pdf             (with images, only with --with-images)
#   stories/NNN_Title.epub            (with images, only with --with-images)
#
# The EPUB is built from Typst's HTML export (not by reflowing the PDF, which
# is messy) via `typst compile --features html`, then packaged with pandoc.
# Requires `pandoc` on PATH in addition to `typst`, and Python 3 with Pillow
# (`pip install pillow`) to downscale the full-resolution art Typst embeds
# as base64 before handing the HTML to pandoc -- large sets (e.g. March of
# the Machine, 61 images) otherwise produce 170MB+ HTML that makes pandoc
# thrash on memory.

set -euo pipefail

cd "$(dirname "$0")"
STORIES_DIR="stories"

WITH_IMAGES=false
if [[ "${1:-}" == "--with-images" ]]; then
    WITH_IMAGES=true
    shift
fi

build_one() {
    local dir="$1"   # e.g. "stories/063 - Secrets of Strixhaven"
    local base
    base="$(basename "$dir")"

    if [[ ! "$base" =~ ^[0-9]{3}\ -\  ]]; then
        echo "Skipping '$base' (doesn't match 'NNN - Title' pattern)" >&2
        return
    fi

    local num="${base%% - *}"
    local title="${base#* - }"
    local wrapper="${STORIES_DIR}/${num}_${title}.typ"

    local files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(find "$dir" -maxdepth 1 -name '*.typ' | sort)

    # Upstream maintains these wrappers too, so only rewrite one when its
    # include list actually differs from the folder contents (ignoring the
    # optional "./" prefix). Rewriting unchanged wrappers just manufactures
    # merge conflicts the next time upstream is pulled.
    local expected=""
    for f in "${files[@]}"; do
        expected+="${f#"$STORIES_DIR"/}"$'\n'
    done
    local current=""
    if [[ -f "$wrapper" ]]; then
        current="$(sed -n 's/^#include "\(\.\/\)\{0,1\}\(.*\)"$/\2/p' "$wrapper")"$'\n'
    fi

    if [[ "$current" == "$expected" ]]; then
        echo "Unchanged $wrapper (${#files[@]} stories)"
    else
        {
            printf '#import "@local/mtgset:0.1.0": conf\n'
            printf '#show: doc => conf("%s", doc)\n\n' "${title//\"/\\\"}"
            printf '%s' "$expected" | sed 's/^\(.*\)$/#include "\1"/'
        } > "$wrapper"
        echo "Wrote $wrapper (${#files[@]} stories)"
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "  no story files found in '$base', skipping compile"
        return
    fi

    typst compile --root . --input with_images=false "$wrapper" "${wrapper%.typ}_no_images.pdf"
    echo "  compiled ${wrapper%.typ}_no_images.pdf"
    build_epub "$wrapper" "$title" "$base" false "${wrapper%.typ}_no_images.epub"

    if [[ "$WITH_IMAGES" == "true" ]]; then
        typst compile --root . "$wrapper"
        echo "  compiled ${wrapper%.typ}.pdf"
        build_epub "$wrapper" "$title" "$base" true "${wrapper%.typ}.epub"
    fi
}

# build_epub WRAPPER TITLE BASE WITH_IMAGES OUT
#
# EPUB: Typst's HTML export -> pandoc. Typst's HTML export bumps every
# heading level by one (its own doc title claims <h1>), so the set-name
# heading lands as <h2> and story titles as <h3>; split-level=3 chapters
# on story titles. The lone <h2> (just the set name, redundant with
# --metadata title) is stripped so it doesn't show up as an empty extra
# chapter/TOC entry.
build_epub() {
    local wrapper="$1" title="$2" base="$3" with_images="$4" out="$5"
    local tag="epub_tmp"
    [[ "$with_images" == "false" ]] && tag="epub_tmp_no_images"
    local html_tmp="${wrapper%.typ}_${tag}.html"
    local html_shrunk="${wrapper%.typ}_${tag}_shrunk.html"
    local herr

    local -a typst_args=(--root . --features html --format html)
    [[ "$with_images" == "false" ]] && typst_args+=(--input with_images=false)

    if ! herr=$(typst compile "${typst_args[@]}" "$wrapper" "$html_tmp" 2>&1); then
        echo "$herr" >&2
        echo "  ERROR: HTML export failed for '$base' (with_images=$with_images), skipping $out" >&2
        rm -f "$html_tmp"
        return
    fi
    if ! herr=$(python3 "$(dirname "$0")/shrink_html_images.py" "$html_tmp" "$html_shrunk" 2>&1); then
        echo "$herr" >&2
        echo "  ERROR: image shrink failed for '$base', skipping $out" >&2
        rm -f "$html_tmp" "$html_shrunk"
        return
    fi
    perl -0777 -pe 's/<h2>.*?<\/h2>//s' -i "$html_shrunk"
    pandoc "$html_shrunk" -o "$out" \
        --split-level=3 --toc --toc-depth=3 \
        --metadata title="$title" --metadata author="Wizards of the Coast" 2>/dev/null
    rm -f "$html_tmp" "$html_shrunk"
    echo "  compiled $out"
}

if [[ $# -eq 0 ]]; then
    for dir in "$STORIES_DIR"/*/; do
        dir="${dir%/}"
        [[ "$(basename "$dir")" =~ ^[0-9]{3}\ -\  ]] || continue
        build_one "$dir"
    done
else
    arg="$1"
    if [[ -d "$STORIES_DIR/$arg" ]]; then
        build_one "$STORIES_DIR/$arg"
    else
        match=""
        for d in "$STORIES_DIR/$arg"*/; do
            [[ -d "$d" ]] || continue
            match="${d%/}"
            break
        done
        if [[ -z "$match" ]]; then
            echo "No set folder found matching '$arg' in $STORIES_DIR/" >&2
            exit 1
        fi
        build_one "$match"
    fi
fi
