#!/bin/bash

##
## Case Name: verify-bootsequence.sh
## Preconditions:
##    UCMv2 is installed in /usr/share/alsa/ucm2 folder
## Description:
##    Run alsactl init to test the initialization settings are correct or not
## Case step:
##    1. check the alsa-lib, alsa-utils version
##    2. save the original amixer settings
##    3. run alsactl init
##    4. restore the original amixer settings
## Expect result:
##    alsactl init runs successfully
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh
# shellcheck source=case-lib/user.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/user.sh

# BootSequence is introduced in alsa-utils 1.2.2-16
ALSAUTILS_VER=1.2.2-16
# BootSequence is introduced in alsa-lib 1.2.2-44
ALSALIB_VER=1.2.2-44
# BootSequence is introduced in alsa-ucm-conf 1.2.3-15
ALSAUCM_VER=1.2.3-15

func_opt_parse_option "$@"
setup_kernel_check_point

start_test
save_alsa_state

main()
{
    local tmp

    dpkg_version_ge "libasound2" "$ALSALIB_VER"
    dpkg_version_ge "alsa-utils" "$ALSAUTILS_VER"
    dpkg_version_ge "alsa-ucm-conf" "$ALSAUCM_VER" || dlogi "alsa-ucm-conf version is too low"

    # alsactl init only applies to SOF card
    [[ -n "$SOFCARD" ]] || die "No SOF card"
    cardname=$(sof-dump-status.py -s "$SOFCARD") || exit 1
    [[ -n "$cardname" ]] || die "Failed to get card $SOFCARD short name"

    tmp=$(mktemp -d) || die "Failed to create tmp folder."
    cd "$tmp"
    dlogi "Indirectly checking the card $cardname UCM2 initial settings (if any) with alsactl init"
    alsactl store -f tmp.conf || die "Failed to save the amixer setting"
    dlogc "alsactl init $SOFCARD"
    alsactl init "$SOFCARD" || die "Failed to run alsactl init"
    alsactl restore -f tmp.conf || die "Failed to restore the amixer setting"
}

main "$@"
