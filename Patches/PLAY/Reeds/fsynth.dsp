import("stdfaust.lib");

// deploy-name: Reeds

// Organelle Reed / Harmonium
// Breathy reed organ with air, warmth, and subtle pulse
//
// knob1: Air - breathiness and noise in the sound
// knob2: Brightness - harmonic content and tone
// knob3: Pulse - tremolo/vibrato intensity
// knob4: Room - ambient space

// MIDI and control inputs
freq = hslider("freq", 440, 20, 20000, 1);
gain = hslider("gain", 0.5, 0, 1, 0.01) : si.smoo;
gate = button("gate");

// Organelle knob controls (0-1 range)
knob1 = hslider("knob1", 0.3, 0, 1, 0.001) : si.smoo;  // Air
knob2 = hslider("knob2", 0.5, 0, 1, 0.001) : si.smoo;  // Brightness
knob3 = hslider("knob3", 0.2, 0, 1, 0.001) : si.smoo;  // Pulse
knob4 = hslider("knob4", 0.3, 0, 1, 0.001) : si.smoo;  // Room

// === AMPLITUDE ENVELOPE ===
// Organ-like but with slight swell for harmonium feel
attack = 0.02 + (knob1 * 0.15);  // Air adds slower attack
decay = 0.1;
sustain = 0.9;
release = 0.08 + (knob1 * 0.2);  // Breathy release

amp_env = gate : en.adsre(attack, decay, sustain, release);

// === PULSE / TREMOLO ===
// Classic harmonium tremolo
pulse_rate = 5.5 + (knob3 * 2.0);  // 5.5 to 7.5 Hz
pulse_depth = knob3 * 0.35;
pulse_lfo = 1 - (pulse_depth * (0.5 + os.osc(pulse_rate) * 0.5));

// Subtle pitch vibrato too
vib_depth = knob3 * 0.004;
vibrato = os.osc(pulse_rate * 0.98) * vib_depth;  // Slightly different rate

// === OSCILLATOR SECTION ===
// Harmonium uses reeds - mix of fundamental and odd harmonics
// Similar to square but softer, with some even harmonics

base_freq = freq * (1 + vibrato);

// Fundamental
fund = os.triangle(base_freq);

// Add harmonics for reed character - weighted toward odds
harm2 = os.triangle(base_freq * 2) * 0.3;   // Soft 2nd
harm3 = os.triangle(base_freq * 3) * 0.5;   // Strong 3rd (reedy)
harm4 = os.triangle(base_freq * 4) * 0.15;  // Soft 4th
harm5 = os.triangle(base_freq * 5) * 0.25;  // 5th for edge
harm6 = os.triangle(base_freq * 6) * 0.1;   // Touch of 6th

// Brightness controls harmonic mix
bright_scale = 0.3 + (knob2 * 0.7);
harmonics = (harm2 + harm3 + harm4 + harm5 + harm6) * bright_scale;

// Core reed tone
reed_tone = (fund * 0.6 + harmonics * 0.4);

// === AIR / BREATH NOISE ===
// Filtered noise for that pump organ breathiness
noise_source = no.noise;

// Bandpass around the fundamental for pitched breath
air_freq = freq * 0.5;
air_bw = 200 + (freq * 0.3);
//air_noise = noise_source : fi.bandpass(2, max(air_freq, 80), max(air_freq + air_bw, 150));

// Simple lowpass filtered noise - much more stable
air_cutoff = max(freq * 0.8, 120);
air_noise = noise_source : fi.lowpass(2, air_cutoff) : fi.highpass(1, 60);


// Also some high air hiss
hiss = noise_source : fi.highpass(1, 3000) : fi.lowpass(1, 8000);
air_mix = air_noise * 0.6 + hiss * 0.4;

// Air envelope - slightly slower attack for pump feel
air_env = gate : en.adsre(0.04 + (knob1 * 0.2), 0.2, 0.7, 0.15);
air_signal = air_mix * air_env * knob1 * 0.15;

// === COMBINE ===
// Mix reed tone with air
raw_mix = reed_tone + air_signal;

// === FILTER ===
// Gentle rolloff, brightness controls
cutoff = 800 + (knob2 * knob2 * 6000);
filtered = raw_mix : fi.lowpass(2, cutoff);

// === APPLY ENVELOPES ===
voiced = filtered * amp_env * pulse_lfo * gain * 0.4;

// === ROOM ===
// Warm room ambience - shorter than pad reverb, more intimate

dry_signal = voiced;

// Room reflections
r1 = int(0.013 * ma.SR);  // 13ms - early reflection
r2 = int(0.027 * ma.SR);  // 27ms
r3 = int(0.041 * ma.SR);  // 41ms
r4 = int(0.059 * ma.SR);  // 59ms
r5 = int(0.073 * ma.SR);  // 73ms

fb = 0.25 + (knob4 * 0.65);  // Moderate feedback

// Room simulation
room1 = dry_signal : @(r1) : fi.lowpass(1, 6000);
room2 = dry_signal : @(r2) : fi.lowpass(1, 5000);
room3 = dry_signal : (+ ~ (@(r3) : *(fb))) : fi.lowpass(1, 4500);
room4 = dry_signal : (+ ~ (@(r4) : *(fb))) : fi.lowpass(1, 4000);
room5 = dry_signal : (+ ~ (@(r5) : *(fb))) : fi.lowpass(1, 3500);

// Stereo room mix
wet_L = (room1 + room3 + room5) * 0.25;
wet_R = (room2 + room4 + room5) * 0.25;

// Dry/wet mix
room_mix = knob4 * 0.6;
out_L = dry_signal * (1 - room_mix * 0.5) + wet_L * room_mix;
out_R = dry_signal * (1 - room_mix * 0.5) + wet_R * room_mix;

// Soft limit
soft_limit(x) = ma.tanh(x * 1.1);

process = soft_limit(out_L * 0.8), soft_limit(out_R * 0.8);