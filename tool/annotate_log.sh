#!/usr/bin/env bash
# Turn a log tail into Actions annotations. The checks API returns those
# lines; the raw log download does not, from every environment.
set -u
file="${1:-}"
if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "::error::annotate_log: missing ${file}"
  exit 0
fi
tail -n 40 "$file" | while IFS= read -r line; do
  safe=$(printf '%s' "$line" | tr -d '\r' | cut -c1-700 | sed 's/%/%25/g')
  echo "::error::${safe}"
done
