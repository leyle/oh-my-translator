#!/bin/bash
# PopClip extension script for OhMyTranslator
# Prefer $POPCLIP_HTML to preserve spaces around inline tags (e.g. <strong>)
# Falls back to $POPCLIP_TEXT for non-browser sources

if [ -n "$POPCLIP_HTML" ]; then
  ENCODED=$(printf '%s' "$POPCLIP_HTML" | python3 -c "
import sys, urllib.parse, re
html = sys.stdin.read()
text = re.sub(r'<[^>]+>', ' ', html)
text = ' '.join(text.split())
print(urllib.parse.quote(text))
")
else
  ENCODED=$(printf '%s' "$POPCLIP_TEXT" | python3 -c "
import sys, urllib.parse
t = sys.stdin.read()
t = ' '.join(t.split())
print(urllib.parse.quote(t))
")
fi

open "omt://translate?text=$ENCODED"
