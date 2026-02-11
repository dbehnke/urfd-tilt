#!/usr/bin/env bash
set -euo pipefail

desc="$(git describe --tags --always --dirty --abbrev=7 --match 'v[0-9]*' 2>/dev/null || true)"

if [[ -z "$desc" ]]; then
  echo "0.0.0~dev"
  exit 0
fi

if [[ "$desc" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "${BASH_REMATCH[1]}"
  exit 0
fi

if [[ "$desc" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g([0-9a-f]+)(-dirty)?$ ]]; then
  base="${BASH_REMATCH[1]}"
  commits="${BASH_REMATCH[2]}"
  sha="${BASH_REMATCH[3]}"
  dirty="${BASH_REMATCH[4]:-}"

  if [[ -n "$dirty" ]]; then
    echo "${base}~${commits}.g${sha}.dirty"
  else
    echo "${base}~${commits}.g${sha}"
  fi
  exit 0
fi

clean_desc="${desc#v}"
clean_desc="${clean_desc//[^0-9A-Za-z.+~-]/-}"
clean_desc="${clean_desc//-/.}"
if [[ "$clean_desc" =~ ^[0-9] ]]; then
  echo "$clean_desc"
else
  echo "0~${clean_desc}"
fi
