#!/bin/sh

export USER_DIR=${USER_DIR:="/usbdrive"}
# PATCH_DIR=${PATCH_DIR:="/usbdrive/Patches"}
# FW_DIR=${FW_DIR:="/root"}
# SCRIPTS_DIR=$FW_DIR/scripts

# should be run from motherhost package installer

mkdir -p $USER_DIR/media/orac/usermodules/sequence

cp -r $USER_DIR/Patches/grids $USER_DIR/media/orac/usermodules/sequence
rm -r $USER_DIR/Patches/grids

exit 0
