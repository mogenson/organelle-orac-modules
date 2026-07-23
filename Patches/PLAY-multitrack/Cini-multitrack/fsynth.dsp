import("stdfaust.lib");

// deploy-name: Cini

// Organelle Ambient Pad
// Lush evolving pad with slow attack, shimmer, and deep space
//
// knob1: Swell - attack and release time (slow evolving envelopes)
// knob2: Tone - lowpass filter, dark to bright
// knob3: Shimmer - high frequency modulated layer
// knob4: Space - reverb/diffusion depth

// MIDI and control inputs
freq = hslider("freq", 440, 20, 20000, 1);
gain = hslider("gain", 0.5, 0, 1, 0.01) : si.smoo;
gate = button("gate");

// Organelle knob controls (0-1 range)
knob1 = hslider("knob1", 0.5, 0, 1, 0.001) : si.smoo;  // Swell
knob2 = hslider("knob2", 0.5, 0, 1, 0.001) : si.smoo;  // Tone
knob3 = hslider("knob3", 0.3, 0, 1, 0.001) : si.smoo;  // Shimmer
knob4 = hslider("knob4", 0.5, 0, 1, 0.001) : si.smoo;  // Space

// === AMPLITUDE ENVELOPE ===
// knob1 controls swell - slow attacks and long releases
attack = 0.1 + (knob1 * 3.0);   // 100ms to 3+ seconds
decay = 1.0;
sustain = 0.8;
release = 0.5 + (knob1 * 4.0);  // 500ms to 4.5 seconds

amp_env = gate : en.adsre(attack, decay, sustain, release);

// === OSCILLATOR SECTION ===
// Multiple detuned saws for thick pad sound

// LFO for slow movement
lfo1 = os.osc(0.13) * 0.003;  // Slow drift
lfo2 = os.osc(0.09) * 0.004;  // Even slower
lfo3 = os.osc(0.17) * 0.002;  // Slightly faster

// Detuned oscillator stack
detune1 = 0.996 + lfo1;
detune2 = 1.000;
detune3 = 1.004 + lfo2;
detune4 = 0.998 + lfo3;
detune5 = 1.002;

osc1 = os.sawtooth(freq * detune1);
osc2 = os.sawtooth(freq * detune2);
osc3 = os.sawtooth(freq * detune3);
osc4 = os.sawtooth(freq * detune4);
osc5 = os.sawtooth(freq * detune5);

// Mix all oscillators
osc_mix = (osc1 + osc2 + osc3 + osc4 + osc5) * 0.2;

// === SHIMMER LAYER ===
// High octave layer with chorus for sparkle
shimmer_freq = freq * 2;  // One octave up
shimmer_lfo = os.osc(0.7) * 0.008;

shimmer1 = os.triangle(shimmer_freq * (1 + shimmer_lfo));
shimmer2 = os.triangle(shimmer_freq * (1 - shimmer_lfo));
shimmer_mix = (shimmer1 + shimmer2) * 0.5;

// Shimmer has its own slower envelope
shimmer_env = gate : en.adsre(attack * 1.5, 1.0, 0.6, release * 1.2);
shimmer_signal = shimmer_mix * shimmer_env * knob3 * 0.3;

// === FILTER SECTION ===
// Gentle lowpass, knob2 controls brightness
cutoff = 200 + (knob2 * knob2 * 8000);
resonance = 1.0 + (knob2 * 1.5);  // Subtle resonance

// Slow filter LFO for movement
filter_lfo = os.osc(0.07) * (500 * knob2);
cutoff_mod = cutoff + filter_lfo;
cutoff_clipped = min(max(cutoff_mod, 50), 16000);

filtered = fi.resonlp(cutoff_clipped, resonance, 1, osc_mix);

// Combine main pad with shimmer
combined = filtered + shimmer_signal;

// === SPACE / REVERB ===
// Lush diffused reverb using delays and feedback

dry_signal = combined * amp_env * gain * 0.42;

// Multiple delay lines for diffusion
dt1 = int(0.037 * ma.SR);  // 37ms
dt2 = int(0.053 * ma.SR);  // 53ms
dt3 = int(0.071 * ma.SR);  // 71ms
dt4 = int(0.097 * ma.SR);  // 97ms

fb = 0.4 + (knob4 * 0.45);  // Feedback amount 0.4 to 0.85

// Diffusion network
diff1 = dry_signal : (+ ~ (@(dt1) : *(fb))) : fi.lowpass(1, 5000);
diff2 = dry_signal : (+ ~ (@(dt2) : *(fb))) : fi.lowpass(1, 4500);
diff3 = dry_signal : (+ ~ (@(dt3) : *(fb))) : fi.lowpass(1, 4000);
diff4 = dry_signal : (+ ~ (@(dt4) : *(fb))) : fi.lowpass(1, 3500);

// Mix diffusion for stereo
wet_L = (diff1 + diff3) * 0.4;
wet_R = (diff2 + diff4) * 0.4;

// Crossfeed for wider stereo
wet_L_wide = wet_L * 0.8 + wet_R * 0.2;
wet_R_wide = wet_R * 0.8 + wet_L * 0.2;

// Dry/wet mix controlled by knob4
space_mix = knob4 * 0.7;  // Max 70% wet
out_L = dry_signal * (1 - space_mix) + wet_L_wide * space_mix;
out_R = dry_signal * (1 - space_mix) + wet_R_wide * space_mix;

// Soft limit
soft_limit(x) = ma.tanh(x);

process = soft_limit(out_L * 1.25), soft_limit(out_R * 1.25);