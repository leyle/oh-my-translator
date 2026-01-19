#!/bin/bash
# translate.sh - Get selected text and open OMT to translate it via URL scheme
# 
# Usage: 
#   ./translate.sh                 # Uses clipboard text
#   ./translate.sh "Hello world"   # Uses provided text
#   ./translate.sh --to=ja "Hello" # Translate to Japanese

# Parse arguments
TARGET_LANG=""
TEXT=""

for arg in "$@"; do
    case $arg in
        --to=*)
            TARGET_LANG="${arg#*=}"
            ;;
        *)
            if [ -z "$TEXT" ]; then
                TEXT="$arg"
            else
                TEXT="$TEXT $arg"
            fi
            ;;
    esac
done

# If no text provided, get from clipboard
if [ -z "$TEXT" ]; then
    TEXT=$(pbpaste)
fi

if [ -z "$TEXT" ]; then
    echo "No text provided or in clipboard"
    exit 1
fi

# URL-encode the text
ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$TEXT'''))")

# Build URL with optional target language
URL="omt://translate?text=$ENCODED"
if [ -n "$TARGET_LANG" ]; then
    URL="$URL&to=$TARGET_LANG"
fi

# Open the URL - works whether app is running or not
open "$URL"
