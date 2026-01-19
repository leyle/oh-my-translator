#!/bin/bash
# PopClip extension script for OhMyTranslator
# $POPCLIP_TEXT contains the selected text

TEXT="$POPCLIP_TEXT"
ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$TEXT'''))")
open "omt://translate?text=$ENCODED"
