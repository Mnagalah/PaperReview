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
PAPERREVIEW_SIGNING_IDENTITY='Explicit certificate'
[[ "$(select_signing_identity "$available")" == 'Explicit certificate' ]]
PAPERREVIEW_SIGNING_IDENTITY='-'
[[ "$(select_signing_identity "$available")" == '-' ]]
echo 'PASS: automatic development signing, signer preservation, explicit selection, and ad-hoc fallback'
