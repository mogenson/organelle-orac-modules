import("stdfaust.lib");

// deploy-name: CZ

// CZ-Style Phase Distortion Synth
// Casio CZ series inspired - phase distortion creates evolving timbres
// knob1: Decay - envelope time
// knob2: Depth - phase distortion amount (timbre)
// knob3: Shape - waveform character (saw → resonant)
// knob4: Space - reverb/chorus

freq = hslider("freq", 440, 20, 20000, 1);
gain = hslider("gain", 0.5, 0, 1, 0.01) : si.smoo;
gate = button("gate");

knob1 = hslider("knob1", 0.4, 0, 1, 0.001) : si.smoo;
knob2 = hslider("knob2", 0.6, 0, 1, 0.001) : si.smoo;
knob3 = hslider("knob3", 0.3, 0, 1, 0.001) : si.smoo;
knob4 = hslider("knob4", 0.3, 0, 1, 0.001) : si.smoo;

// === ENVELOPES ===
attack = 0.015;
decay = 0.1 + (knob1 * 1.5);
sustain = 0.3;
release = 0.1 + (knob1 * 0.8);
amp_env = gate : en.adsre(attack, decay, sustain, release);

// Distortion envelope - faster decay for that CZ pluck
dist_decay = 0.03 + (knob1 * 0.5);
dist_env = gate : en.adsre(0.01, dist_decay, 0.1, 0.1);

// === PHASE DISTORTION OSCILLATOR ===
// Basic phasor (0 to 1 ramp)
phasor = os.phasor(1, freq);

// Phase distortion amount (envelope controlled)
base_distort = 0.1 + (knob2 * 0.85);
distortion = base_distort * (0.3 + dist_env * 0.7);

// Shape morphs between different distortion curves
shape = knob3;

// Phase distortion function
// Creates saw-like, resonant, and pulse-like tones depending on shape
distorted_phase(p, d, s) = select2(s < 0.5,
    // Resonant mode (shape >= 0.5): double-bump creates formant peak
    resonant_phase(p, d, (s - 0.5) * 2),
    // Saw mode (shape < 0.5): accelerate first half, decelerate second
    saw_phase(p, d, s * 2)
);

// Saw-like phase distortion
saw_phase(p, d, s) = result
with {
    // Mix between linear and exponential-ish curve
    curve = 1 + d * 4 * (1 - s);  // More curve with higher distortion
    half = 0.5 - (d * 0.3 * s);   // Adjust inflection point
    p1 = p / half : min(1);
    p2 = (p - half) / (1 - half) : max(0);
    result = select2(p < half,
        0.5 + pow(p2, 1/curve) * 0.5,
        pow(p1, curve) * 0.5
    );
};

// Resonant phase distortion (CZ resonant waveforms)
resonant_phase(p, d, s) = result
with {
    // Number of "bumps" in the phase - creates resonant peak
    bumps = 1 + d * (2 + s * 3);  // 1 to 6 bumps
    result = p * bumps : ma.frac;
};

// Apply phase distortion and read cosine
pd_osc = cos(distorted_phase(phasor, distortion, shape) * 2 * ma.PI);

// === SECOND OSCILLATOR (detuned, less distortion) ===
phasor2 = os.phasor(1, freq * 1.003);
pd_osc2 = cos(distorted_phase(phasor2, distortion * 0.7, shape) * 2 * ma.PI);

// Mix oscillators
osc_mix = pd_osc * 0.6 + pd_osc2 * 0.15;

// === OUTPUT ===
dry_signal = osc_mix * amp_env * gain * 0.5;

// === CHORUS/REVERB ===
// Light chorus for stereo width
chorus_lfo = os.osc(0.8) * 0.002 * ma.SR;
chorus_L = dry_signal : de.fdelay(4096, 150 + chorus_lfo);
chorus_R = dry_signal : de.fdelay(4096, 180 - chorus_lfo);

// Simple reverb
fb = 0.25 + (knob4 * 0.4);
rev_L = chorus_L : (+ ~ (@(int(0.035 * ma.SR)) : *(fb))) : fi.lowpass(1, 5000);
rev_R = chorus_R : (+ ~ (@(int(0.042 * ma.SR)) : *(fb))) : fi.lowpass(1, 5000);

space_mix = knob4 * 0.5;
out_L = dry_signal * (1 - space_mix) + (chorus_L * 0.3 + rev_L * 0.7) * space_mix;
out_R = dry_signal * (1 - space_mix) + (chorus_R * 0.3 + rev_R * 0.7) * space_mix;

soft_limit(x) = ma.tanh(x);
process = soft_limit(out_L), soft_limit(out_R);
