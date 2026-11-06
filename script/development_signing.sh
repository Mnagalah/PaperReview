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

# A certificate-signed app must keep its designated requirement on an ordinary
# rebuild. An explicit signer change is the caller's deliberate opt-in instead.
signing_continuity_is_valid() {
  local current_signer="$1" current_requirement="$2" next_requirement="$3"
  [[ -n "${PAPERREVIEW_SIGNING_IDENTITY:-}" || -z "$current_signer" ||
     ( -n "$current_requirement" && "$current_requirement" == "$next_requirement" ) ]]
}
