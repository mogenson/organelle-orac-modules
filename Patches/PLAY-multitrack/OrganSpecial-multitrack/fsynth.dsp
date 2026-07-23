import("stdfaust.lib");

// deploy-name: Organ Special

// Organelle Church Organ
// knob1: Swell - attack/release time (organ swell pedal)
// knob2: Brightness - upper harmonic content
// knob3: Vibrato - depth and Leslie-style chorus
// knob4: Cathedral - reverb depth

freq = hslider("freq", 440, 20, 20000, 1);
gain = hslider("gain", 0.5, 0, 1, 0.01) : si.smoo;
gate = button("gate");

knob1 = hslider("knob1", 0.4, 0, 1, 0.001) : si.smoo;
knob2 = hslider("knob2", 0.6, 0, 1, 0.001) : si.smoo;
knob3 = hslider("knob3", 0.3, 0, 1, 0.001) : si.smoo;
knob4 = hslider("knob4", 0.5, 0, 1, 0.001) : si.smoo;

// === DRAWBAR/FOOTAGE SYSTEM (additive synthesis) ===
// Classic organ footages: 16' 8' 5-1/3' 4' 2-2/3' 2' 1-3/5' 1-1/3' 1'
// Using sine waves like real organ pipes

// Vibrato - slow, subtle pitch modulation
vib_rate = 5.8 + (knob3 * 1.2);  // 5.8-7 Hz
vib_depth = knob3 * 0.008;
vibrato = os.osc(vib_rate) * vib_depth * freq;
freq_vib = freq + vibrato;

// Sub-octave (16' stop)
draw_16 = os.osc(freq_vib * 0.5) * 0.4;

// Fundamental (8' stop - main pitch)
draw_8 = os.osc(freq_vib) * 0.7;

// Fifth above (5-1/3' stop - perfect fifth)
draw_5 = os.osc(freq_vib * 1.5) * (0.3 + knob2 * 0.3);

// Octave up (4' stop)
draw_4 = os.osc(freq_vib * 2.0) * (0.4 + knob2 * 0.4);

// Fifth + octave (2-2/3' stop)
draw_2_2_3 = os.osc(freq_vib * 3.0) * (knob2 * 0.35);

// Two octaves up (2' stop)
draw_2 = os.osc(freq_vib * 4.0) * (knob2 * knob2 * 0.3);

// Tierce (1-3/5' stop - third harmonic)
draw_1_3_5 = os.osc(freq_vib * 5.0) * (knob2 * knob2 * 0.2);

// Larigot (1-1/3' stop)
draw_1_1_3 = os.osc(freq_vib * 6.0) * (knob2 * knob2 * 0.15);

// High mixture (1' stop)
draw_1 = os.osc(freq_vib * 8.0) * (knob2 * knob2 * knob2 * 0.12);

// Mix all drawbars
organ_tone = draw_16 + draw_8 + draw_5 + draw_4 + draw_2_2_3 +
             draw_2 + draw_1_3_5 + draw_1_1_3 + draw_1;

// Normalize
organ_mixed = organ_tone * 0.25;

// === SWELL ENVELOPE (organ swell pedal) ===
attack = 0.02 + (knob1 * 1.5);   // 20ms to 1.5s swell
decay = 0.1;
sustain = 1.0;                    // Full sustain
release = 0.05 + (knob1 * 2.0);  // 50ms to 2s release
swell_env = gate : en.adsre(attack, decay, sustain, release);

// Apply swell envelope
organ_signal = organ_mixed * swell_env * gain * 0.6;

// === LESLIE/CHORUS EFFECT ===
// Dual pitch-shifted delays for chorus/Leslie simulation
chorus_depth = knob3 * 0.3;

lfo1 = os.osc(0.71) * 0.002 * ma.SR * knob3;
lfo2 = os.osc(0.53) * 0.002 * ma.SR * knob3;

chorus_L = organ_signal : de.fdelay(8192, 200 + lfo1);
chorus_R = organ_signal : de.fdelay(8192, 230 + lfo2);

dry_mix = 1 - (chorus_depth * 0.6);
organ_chorused_L = organ_signal * dry_mix + chorus_L * chorus_depth;
organ_chorused_R = organ_signal * dry_mix + chorus_R * chorus_depth;

// === CATHEDRAL REVERB (multiple diffusion stages) ===
reverb_mix = knob4 * 0.8;
feedback = 0.3 + (knob4 * 0.5);

// Multiple delay lines for cathedral spaciousness
diff1_L = organ_chorused_L : (+ ~ (@(int(0.043 * ma.SR)) : *(feedback))) : fi.lowpass(1, 4500);
diff2_L = organ_chorused_L : (+ ~ (@(int(0.067 * ma.SR)) : *(feedback))) : fi.lowpass(1, 4000);
diff3_L = organ_chorused_L : (+ ~ (@(int(0.091 * ma.SR)) : *(feedback))) : fi.lowpass(1, 3500);
diff4_L = organ_chorused_L : (+ ~ (@(int(0.127 * ma.SR)) : *(feedback))) : fi.lowpass(1, 3000);

diff1_R = organ_chorused_R : (+ ~ (@(int(0.037 * ma.SR)) : *(feedback))) : fi.lowpass(1, 4500);
diff2_R = organ_chorused_R : (+ ~ (@(int(0.059 * ma.SR)) : *(feedback))) : fi.lowpass(1, 4000);
diff3_R = organ_chorused_R : (+ ~ (@(int(0.083 * ma.SR)) : *(feedback))) : fi.lowpass(1, 3500);
diff4_R = organ_chorused_R : (+ ~ (@(int(0.113 * ma.SR)) : *(feedback))) : fi.lowpass(1, 3000);

wet_L = (diff1_L + diff2_L + diff3_L + diff4_L) * 0.25;
wet_R = (diff1_R + diff2_R + diff3_R + diff4_R) * 0.25;

// Mix dry and wet with cross-feeding for width
out_L = organ_chorused_L * (1 - reverb_mix) + (wet_L * 0.8 + wet_R * 0.2) * reverb_mix;
out_R = organ_chorused_R * (1 - reverb_mix) + (wet_R * 0.8 + wet_L * 0.2) * reverb_mix;

// Gentle limiting
soft_limit(x) = ma.tanh(x * 1.1);
process = soft_limit(out_L), soft_limit(out_R);
