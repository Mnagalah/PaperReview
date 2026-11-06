#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/script/development_signing.sh"
unset PAPERREVIEW_SIGNING_IDENTITY
available='  1) 1111111111111111111111111111111111111111 "Apple Development: First Developer (TEAMONE)"
  2) 2222222222222222222222222222222222222222 "Apple Development: Other Developer (TEAMTWO)"
     2 valid identities found'
[[ "$(select_signing_identity "$available")" == 1111111111111111111111111111111111111111 ]]
[[ "$(select_signing_identity "$available" 'Apple Development: Other Developer (TEAMTWO)')" == 'Apple Development: Other Developer (TEAMTWO)' ]]
[[ "$(select_signing_identity "$available" 'Apple Development: Removed Developer (OLDTEAM)')" == 1111111111111111111111111111111111111111 ]]
[[ "$(select_signing_identity '     0 valid identities found')" == '-' ]]
[[ "$(signing_continuity_is_valid 'Apple Development: First Developer (TEAMONE)' 'designated => stable' 'designated => stable'; echo $?)" == 0 ]]
if signing_continuity_is_valid 'Apple Development: First Developer (TEAMONE)' 'designated => stable' 'designated => changed'; then
  echo 'FAIL: signed rebuild accepted a changed requirement' >&2; exit 1
fi
if signing_continuity_is_valid 'Apple Development: First Developer (TEAMONE)' '' ''; then
  echo 'FAIL: signed rebuild accepted missing requirements' >&2; exit 1
fi
signing_continuity_is_valid '' 'old ad-hoc requirement' 'new certificate requirement'
PAPERREVIEW_SIGNING_IDENTITY='Explicit certificate'
[[ "$(select_signing_identity "$available")" == 'Explicit certificate' ]]
signing_continuity_is_valid 'previous certificate' 'old requirement' 'new requirement'
PAPERREVIEW_SIGNING_IDENTITY='-'
[[ "$(select_signing_identity "$available")" == '-' ]]
echo 'PASS: signing selection, stable requirement, drift rejection, explicit signer change, and first certificate upgrade'
