import("stdfaust.lib");

// deploy-name: Lead HQ

// Organelle Mono Lead
// Expressive monophonic lead synth with drive, vibrato, and chorus
//
// knob1: Decay - amplitude envelope decay/release
// knob2: Brightness - filter cutoff with envelope modulation
// knob3: Drive - saturation and harmonic intensity
// knob4: Chorus - BBD-style stereo chorus depth

// MIDI and control inputs
freq = hslider("freq", 440, 20, 20000, 1);
gain = hslider("gain", 0.5, 0, 1, 0.01);
gate = button("gate");

// Organelle knob controls (0-1 range)
knob1 = hslider("knob1", 0.4, 0, 1, 0.001) : si.smoo;  // Decay
knob2 = hslider("knob2", 0.6, 0, 1, 0.001) : si.smoo;  // Brightness
knob3 = hslider("knob3", 0.3, 0, 1, 0.001) : si.smoo;  // Drive
knob4 = hslider("knob4", 0.3, 0, 1, 0.001) : si.smoo;  // Chorus

// === VIBRATO ===
freq_smooth = freq;
vib_rate = 5.0;
vib_depth = 0.006;
vibrato = os.osc(vib_rate) * vib_depth * freq_smooth;
final_freq = freq_smooth + vibrato;

// === OSCILLATOR SECTION ===
osc1 = os.sawtooth(final_freq);
detune = 1.008;
osc2 = os.sawtooth(final_freq * detune);
osc_sub = os.square(final_freq * 0.5) * 0.5;

sub_amount = 0.3 + (knob3 * 0.4);
osc_mix = (osc1 + osc2) * 0.5 + osc_sub * sub_amount;

// === FILTER SECTION ===
filt_env = gate : en.adsre(0.005, 0.1 + (knob1 * 1.9), 0.3, 0.1);

base_cutoff = 200 + (knob2 * knob2 * 6000);
env_depth = 1000 + (knob2 * 4000);
cutoff = base_cutoff + (filt_env * env_depth);
cutoff_clipped = min(cutoff, 16000);

resonance = 2.0 + (knob2 * 3.0);
filtered = fi.resonlp(cutoff_clipped, resonance, 1, osc_mix);

// === DRIVE / SATURATION ===
drive_amount = 1.0 + (knob3 * 4.0);
saturate(x) = ma.tanh(x * drive_amount) / max(0.5, drive_amount * 0.3);
driven = filtered : saturate;

// Presence: blend in some high-passed signal for edge
highs = driven : fi.highpass(1, 2000);
presence_amount = knob3 * 0.3;
presence = driven + (highs * presence_amount);

// === AMPLITUDE ENVELOPE ===
attack = 0.008;
decay = 0.1 + (knob1 * 0.4);
sustain = 0.6;
release = 0.2 + (knob1 * 1.8);

amp_env = gate : en.adsre(attack, decay, sustain, release);

// === OUTPUT ===
dry_signal = presence * amp_env * gain * 0.25;

// === BBD-STYLE STEREO CHORUS ===
// Modulated delay lines with slow LFOs, 90-degree phase offset for stereo
chorus_rate = 0.8;  // LFO rate in Hz
chorus_base_delay = 0.007 * ma.SR;  // 7ms base delay
chorus_mod_depth = knob4 * 0.004 * ma.SR;  // 0-4ms modulation depth

// LFOs with phase offset for stereo spread
lfo_L = os.osc(chorus_rate);
lfo_R = os.oscp(chorus_rate, 0.5);  // 90-degree phase offset

// Modulated delay times
delay_time_L = chorus_base_delay + (lfo_L * chorus_mod_depth);
delay_time_R = chorus_base_delay + (lfo_R * chorus_mod_depth);

// Delay lines (using de.fdelay for fractional delay)
max_delay = int(0.02 * ma.SR);  // 20ms max
chorus_L = dry_signal : de.fdelay(max_delay, delay_time_L);
chorus_R = dry_signal : de.fdelay(max_delay, delay_time_R);

// Mix dry and wet based on knob4
chorus_mix = knob4 * 0.6;  // Max 60% wet for usable range
out_L = dry_signal * (1 - chorus_mix) + chorus_L * chorus_mix;
out_R = dry_signal * (1 - chorus_mix) + chorus_R * chorus_mix;

// Final soft limit
soft_limit(x) = ma.tanh(x * 1.1);

process = soft_limit(out_L * 0.5), soft_limit(out_R * 0.7);
