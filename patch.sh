#!/bin/bash
export REPO=$PWD/repo
export B2G_TREEID_SH="$PWD/patches/treeid.sh"
export B2G_HASHED_FILES="$PWD/patches/vendorsetup.sh ${B2G_TREEID_SH} $PWD/.config $PWD/patches/patch.sh"
export B2G_PATCH_DIRS_OVERRIDE=patches

. patches/vendorsetup.sh
