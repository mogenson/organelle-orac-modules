#!/bin/sh

export USER_DIR=${USER_DIR:="/usbdrive"}
# PATCH_DIR=${PATCH_DIR:="/usbdrive/Patches"}
# FW_DIR=${FW_DIR:="/root"}
# SCRIPTS_DIR=$FW_DIR/scripts

# should be run from motherhost package installer

mkdir -p $USER_DIR/media/orac/usermodules/sampler
mkdir -p $USER_DIR/media/samples/kit-1
mkdir -p $USER_DIR/media/samples/kit-2
mkdir -p $USER_DIR/media/samples/kit-3
mkdir -p $USER_DIR/media/samples/kit-4
mkdir -p $USER_DIR/media/samples/kit-5
mkdir -p $USER_DIR/media/samples/kit-6
mkdir -p $USER_DIR/media/samples/kit-7
mkdir -p $USER_DIR/media/samples/kit-8
mkdir -p $USER_DIR/media/samples/kit-9
mkdir -p $USER_DIR/media/samples/kit-10
mkdir -p $USER_DIR/media/samples/kit-11
mkdir -p $USER_DIR/media/samples/kit-12
mkdir -p $USER_DIR/media/samples/kit-13
mkdir -p $USER_DIR/media/samples/kit-14
mkdir -p $USER_DIR/media/samples/kit-15
mkdir -p $USER_DIR/media/samples/kit-16
mkdir -p $USER_DIR/media/samples/kit-17
mkdir -p $USER_DIR/media/samples/kit-18
mkdir -p $USER_DIR/media/samples/kit-19
mkdir -p $USER_DIR/media/samples/kit-20
mkdir -p $USER_DIR/media/samples/kit-21
mkdir -p $USER_DIR/media/samples/kit-22
mkdir -p $USER_DIR/media/samples/kit-23
mkdir -p $USER_DIR/media/samples/kit-24

cp -r $USER_DIR/Patches/percussions $USER_DIR/media/orac/usermodules/sampler
rm -r $USER_DIR/Patches/percussions

exit 0
