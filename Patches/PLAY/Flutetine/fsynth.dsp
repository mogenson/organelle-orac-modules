declare name "Organelle Soft Tines";
import("stdfaust.lib");

// deploy-name: Flutetine

// knob1: Tone
// knob2: Bite
// knob3: Tremolo
// knob4: Space

////////////////////////////////////////////////////////////////////////////////
// Required Organelle controls (DO NOT CHANGE / DO NOT ADD MORE UI CONTROLS)
////////////////////////////////////////////////////////////////////////////////
freq = hslider("freq", 440, 20, 2000, 1);
gain = hslider("gain", 0.5, 0, 1, 0.01) : si.smoo;
gate = button("gate");
knob1 = hslider("knob1", 0.5, 0, 1, 0.001) : si.smoo;  // Tone (dark <-> bright)
knob2 = hslider("knob2", 0.5, 0, 1, 0.001) : si.smoo;  // Bite (soft <-> bark)
knob3 = hslider("knob3", 0.5, 0, 1, 0.001) : si.smoo;  // Tremolo (off <-> deep)
knob4 = hslider("knob4", 0.3, 0, 1, 0.001) : si.smoo;  // Space (dry <-> wet)

////////////////////////////////////////////////////////////////////////////////
// Helpers (no UI)
////////////////////////////////////////////////////////////////////////////////
// exponential-style mapping without linexp
expmap(x, lo, hi) = lo * pow(hi / lo, x);

// gentle soft clip / limiter
softclip(x) = x / (1 + abs(x));

// simple filters (known 1-in/1-out signatures)
lpf(fc) = fi.lowpass(1, fc);
hpf(fc) = fi.highpass(1, fc);
bpf(lo, hi) = hpf(lo) : lpf(hi);

// mapped controls
tone  = knob1;
bite  = knob2;
space = knob4;

// tone-dependent lowpass cutoff (dark->bright)
lpCut = expmap(tone, 350, 8500);

// bite-dependent drive
drive = 1 + (bite * 7);

// tremolo (post-voice)
tremRate = 5.0;
tremLFO  = (os.osc(tremRate) * 0.5) + 0.5;          // 0..1
trem     = (1 - knob3) + (knob3 * tremLFO);         // 1..LFO

// envelopes (avoid clicks)
ampEnv = gate : en.adsre(0.006, 0.28, 0.55, 0.22);  // main body
atkEnv = gate : en.adsre(0.0008, 0.050, 0.0, 0.03); // tine transient

// subtle vibrato (fixed tiny amount)
vib = (os.osc(5.2) * 0.0025) + 1;

////////////////////////////////////////////////////////////////////////////////
// Voice (exciter/body) [mono]
////////////////////////////////////////////////////////////////////////////////
f0 = freq * vib;

// --- Body: warm partial stack + mellow filtering
p1 = os.osc(f0);
p2 = os.osc(f0 * 2.01) * 0.22;
p3 = os.osc(f0 * 3.00) * 0.10;
body0 = (p1 + p2 + p3) * 0.55;

// "wood" coloration using a gentle band emphasis (no resonbp)
woodLo = 380;
woodHi = 980;
wood   = (body0 : bpf(woodLo, woodHi)) * 0.18;

body = (body0 + wood) : lpf(lpCut) : *(ampEnv);

// --- Exciter: short bright tine (noise burst + bright partial)
tineFc = expmap(tone, 1400, 5600);
tineLo = max(300, tineFc * 0.70);
tineHi = min(12000, tineFc * 1.55);

tineN = (no.noise : bpf(tineLo, tineHi)) * 0.55;
tineP = (os.osc(f0 * 8.0) : lpf(9000)) * 0.18;

// Bite adds "bark": more exciter + a mid bump + more drive
barkLo = 700;
barkHi = 2200;

exc0 = (tineN + tineP) * (0.55 + 1.6 * bite);
exc  = (exc0 + (exc0 : bpf(barkLo, barkHi)) * (0.35 * bite)) : *(atkEnv);

// combine + drive + final tone LP
voiceRaw = body + exc;
voiceDrv = softclip(voiceRaw * drive);
voice    = (voiceDrv : lpf(lpCut)) * gain;

////////////////////////////////////////////////////////////////////////////////
// Tremolo (post-voice, pre-reverb)
////////////////////////////////////////////////////////////////////////////////
preFX = voice * trem;

////////////////////////////////////////////////////////////////////////////////
// Reverb (simple stereo feedback delay network; space = wet amount)
////////////////////////////////////////////////////////////////////////////////
fb     = 0.78;
dampFc = 5200;

fbDelay(d) = +~(_ : @(d) : *(fb)) : lpf(dampFc);

// mono -> stereo wet
revStereo(x) =
  x <:
    ( fbDelay(1493) * 0.55,
      fbDelay(1607) * 0.55 );

dryWet(d, w, m) = d * (1 - m) + w * m;

wet = preFX : revStereo;
outL = dryWet(preFX, wet : select2(0), space);
outR = dryWet(preFX, wet : select2(1), space);

////////////////////////////////////////////////////////////////////////////////
// Final process routing (stereo out, safe)
////////////////////////////////////////////////////////////////////////////////
// Output scaled after softclip to preserve clipping character
process = (outL, outR) : (softclip, softclip) : (*(0.5), *(0.5));
