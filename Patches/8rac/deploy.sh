#!/bin/sh

export USER_DIR=${USER_DIR:="/usbdrive"}
# PATCH_DIR=${PATCH_DIR:="/usbdrive/Patches"}
# FW_DIR=${FW_DIR:="/root"}
# SCRIPTS_DIR=$FW_DIR/scripts

oscsend localhost 4001 /oled/aux/line/2 s "installing"
oscsend localhost 4001 /oled/aux/line/3 s "8rac"

mkdir -p $USER_DIR/media/soundfonts
mkdir -p $USER_DIR/media/octaloops
mkdir -p $USER_DIR/media/quantplay
mkdir -p $USER_DIR/media/captures
mkdir -p $USER_DIR/media/samples
mkdir -p $USER_DIR/media/recordings
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
mkdir -p $USER_DIR/media/usermodules/effects/comp
mkdir -p $USER_DIR/media/usermodules/effects/delay
mkdir -p $USER_DIR/media/usermodules/effects/drive
mkdir -p $USER_DIR/media/usermodules/effects/filter
mkdir -p $USER_DIR/media/usermodules/effects/mod
mkdir -p $USER_DIR/media/usermodules/effects/reverb
mkdir -p $USER_DIR/media/usermodules/instruments/drum
mkdir -p $USER_DIR/media/usermodules/instruments/sampler
mkdir -p $USER_DIR/media/usermodules/instruments/synth
mkdir -p $USER_DIR/media/usermodules/mod-sources
mkdir -p $USER_DIR/media/usermodules/router
mkdir -p $USER_DIR/media/usermodules/sequence
mkdir -p $USER_DIR/media/usermodules/utility/audio
mkdir -p $USER_DIR/media/usermodules/utility/cv
mkdir -p $USER_DIR/media/usermodules/utility/midi
mkdir -p $USER_DIR/media/usermodules/utility/visual
mkdir -p $USER_DIR/media/usermodules/utility/clocks

mkdir -p $USER_DIR/data/orac/presets
cp -r data/presets/*  $USER_DIR/data/orac/presets
cp data/rack.json $USER_DIR/data/orac

chmod 555 $USER_DIR/data/orac/presets/Init

exit 0
