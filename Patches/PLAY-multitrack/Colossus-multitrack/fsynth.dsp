import("stdfaust.lib");

// deploy-name: Colossus

// Rhodes-style Electric Piano
// knob1: Envelope - decay/release time
// knob2: Tone - brightness/bark
// knob3: Pitch - from 0 up to normal pitch
// knob4: Space - reverb depth

freq = hslider("freq", 440, 20, 20000, 1);
gain = hslider("gain", 0.5, 0, 1, 0.01) : si.smoo;
gate = button("gate");

knob1 = hslider("knob1", 0.5, 0, 1, 0.001) : si.smoo;
knob2 = hslider("knob2", 0.5, 0, 1, 0.001) : si.smoo;
knob3 = hslider("knob3", 1.0, 0, 1, 0.001) : si.smoo;
knob4 = hslider("knob4", 0.3, 0, 1, 0.001) : si.smoo;

// Pitch control - knob3: 0 = 2 octaves down, 1 = normal pitch
pitch_ratio = ba.semi2ratio((knob3 - 1) * 24);  // -24 to 0 semitones
actual_freq = freq * pitch_ratio;

// === RHODES TONE GENERATION ===
// Fundamental sine
fundamental = os.osc(actual_freq);

// Harmonics for tine/bell character
harmonic2 = os.osc(actual_freq * 2) * 0.5;
harmonic3 = os.osc(actual_freq * 3) * 0.25;
harmonic4 = os.osc(actual_freq * 4) * 0.1;

// Inharmonic "bell" component (slightly detuned)
bell = os.osc(actual_freq * 7.1) * 0.08;

// Mix harmonics - more harmonics at higher tone settings
base_mix = fundamental + harmonic2 * knob2 + harmonic3 * knob2 * 0.8;
bright_mix = harmonic4 * knob2 + bell * knob2;
tine = base_mix + bright_mix;

// === BARK ENVELOPE ===
// Fast attack brightness that decays - characteristic Rhodes sound
bark_env = en.ar(0.001, 0.03 + knob2 * 0.1, gate);
// Guard bark filter - clamp to avoid blowup near Nyquist
bark_freq = max(actual_freq, 50);
bark_low = min(bark_freq * 3, ma.SR * 0.38);
bark_high = min(bark_freq * 8, ma.SR * 0.4);
bark = no.noise : fi.bandpass(2, bark_low, max(bark_high, bark_low + 50)) * bark_env * knob2 * 0.15 * (actual_freq > 40);

// === AMPLITUDE ENVELOPE ===
attack = 0.008;
decay = 0.1 + knob1 * 0.5;
sustain = 0.5 + knob1 * 0.3;
release = 0.1 + knob1 * 1.5;
amp_env = gate : en.adsre(attack, decay, sustain, release);

// === TREMOLO (subtle) ===
trem = 1 - (os.osc(5.5) * 0.03);

// Combine
dry = (tine + bark) * amp_env * trem * gain * 0.4;

// === STEREO REVERB ===
reverb_mix = knob4 * 0.7;
fb = 0.4 + knob4 * 0.4;

// Simple diffused reverb
rev1_L = dry : (+ ~ (@(int(0.031 * ma.SR)) : *(fb))) : fi.lowpass(1, 4000);
rev2_L = dry : (+ ~ (@(int(0.047 * ma.SR)) : *(fb))) : fi.lowpass(1, 3500);
rev3_L = dry : (+ ~ (@(int(0.071 * ma.SR)) : *(fb))) : fi.lowpass(1, 3000);

rev1_R = dry : (+ ~ (@(int(0.037 * ma.SR)) : *(fb))) : fi.lowpass(1, 4000);
rev2_R = dry : (+ ~ (@(int(0.053 * ma.SR)) : *(fb))) : fi.lowpass(1, 3500);
rev3_R = dry : (+ ~ (@(int(0.079 * ma.SR)) : *(fb))) : fi.lowpass(1, 3000);

wet_L = (rev1_L + rev2_L + rev3_L) * 0.33;
wet_R = (rev1_R + rev2_R + rev3_R) * 0.33;

out_L = ma.tanh((dry * (1 - reverb_mix) + wet_L * reverb_mix) * 0.5);
out_R = ma.tanh((dry * (1 - reverb_mix) + wet_R * reverb_mix) * 0.5);

process = out_L, out_R;
