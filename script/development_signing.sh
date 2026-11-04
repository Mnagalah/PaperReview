#!/bin/bash

# Prefer the installed app's signer so adding another certificate does not
# change its TCC identity. Explicit configuration takes precedence.
select_signing_identity() {
  if [[ -n "${PAPERREVIEW_SIGNING_IDENTITY:-}" ]]; then
    printf '%s\n' "$PAPERREVIEW_SIGNING_IDENTITY"
    return
  fi
  local available="$1" current="${2:-}" identity
  if [[ -n "$current" ]] && printf '%s\n' "$available" | grep -Fq -- "\"$current\""; then
    printf '%s\n' "$current"
    return
  fi
  identity="$(printf '%s\n' "$available" | awk '/"Apple Development: / { print $2; exit }')"
  printf '%s\n' "${identity:--}"
}
