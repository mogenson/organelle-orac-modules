echo "Compiling Faust..."

# creates Pd object
faust2puredata fsynth.dsp

# move compiled external to lib/
mv fsynth~.pd_linux lib/

# remove build artifacts
rm -rf faust.*
