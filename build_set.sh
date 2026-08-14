#!/usr/bin/env bash
#
# build_set.sh — regenerate a set's combined "stories/NNN_Title.typ" wrapper
# from whatever story .typ files actually exist in "stories/NNN - Title/",
# then compile it to PDF (with and without images).
#
# This replaces hand-editing the #include list every time a story is added
# to a set folder, and replaces manually typing the `typst compile` command
# from the README.
#
# Usage:
#   ./build_set.sh                                    # process every set folder
#   ./build_set.sh "063 - Secrets of Strixhaven"       # one set, by folder name
#   ./build_set.sh 063                                 # one set, by number prefix
#
# Output per set (written into stories/, alongside the set folder):
#   stories/NNN_Title.typ             (regenerated wrapper)
#   stories/NNN_Title.pdf             (with images)
#   stories/NNN_Title_no_images.pdf   (without images)

set -euo pipefail

cd "$(dirname "$0")"
STORIES_DIR="stories"

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

    {
        printf '#import "@local/mtgset:0.1.0": conf\n'
        printf '#show: doc => conf("%s", doc)\n\n' "${title//\"/\\\"}"
        for f in "${files[@]}"; do
            printf '#include "%s"\n' "${f#"$STORIES_DIR"/}"
        done
    } > "$wrapper"

    echo "Wrote $wrapper (${#files[@]} stories)"

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "  no story files found in '$base', skipping compile"
        return
    fi

    typst compile --root . "$wrapper"
    echo "  compiled ${wrapper%.typ}.pdf"

    typst compile --root . --input with_images=false "$wrapper" "${wrapper%.typ}_no_images.pdf"
    echo "  compiled ${wrapper%.typ}_no_images.pdf"
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
