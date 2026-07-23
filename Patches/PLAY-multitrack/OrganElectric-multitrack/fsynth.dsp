import("stdfaust.lib");

// deploy-name: Organ Electric

// Organelle Jazz Organ (Hammond Style)
// knob1: Percussion - percussive attack intensity & decay
// knob2: Drawbars - harmonic balance (mellow to bright)
// knob3: Drive - tube overdrive saturation
// knob4: Rotary - rotary speaker speed (slow/fast)

freq = hslider("freq", 440, 20, 20000, 1);
gain = hslider("gain", 0.5, 0, 1, 0.01) : si.smoo;
gate = button("gate");

knob1 = hslider("knob1", 0.5, 0, 1, 0.001) : si.smoo;
knob2 = hslider("knob2", 0.5, 0, 1, 0.001) : si.smoo;
knob3 = hslider("knob3", 0.3, 0, 1, 0.001) : si.smoo;
knob4 = hslider("knob4", 0.3, 0, 1, 0.001);  // No smooth - we want stepped feel

// === KEY CLICK ===
// Hammond's famous mechanical click on key press
click_env = gate : en.adsre(0.001, 0.008, 0.0, 0.005);
click_noise = no.noise : fi.bandpass(2, 2000, 5000);
key_click = click_noise * click_env * (knob1 * 0.1);

// === PERCUSSION ===
// The percussive 2nd or 3rd harmonic attack
perc_env = gate : en.adsre(0.001, 0.08 + (knob1 * 0.3), 0.0, 0.02);
perc_harm = os.osc(freq * 3);  // 3rd harmonic percussion
percussion = perc_harm * perc_env * knob1 * 0.25;

// === TONEWHEEL HARMONICS (Drawbar simulation) ===
// Classic Hammond drawbar footage: 16', 5-1/3', 8', 4', 2-2/3', 2', 1-3/5', 1-1/3', 1'
// Simplified to key harmonics with knob2 controlling balance

// Sub (16' - one octave down)
sub = os.osc(freq * 0.5);

// Fundamental (8')
fund = os.osc(freq);

// 5th above sub (5-1/3' - creates that Hammond "quint")
quint_low = os.osc(freq * 1.5);

// Octave (4')
oct = os.osc(freq * 2);

// 5th (2-2/3')
quint = os.osc(freq * 3);

// 2nd octave (2')
oct2 = os.osc(freq * 4);

// Major 3rd (1-3/5')
third = os.osc(freq * 5);

// 5th up (1-1/3')
quint_high = os.osc(freq * 6);

// 3rd octave (1')
oct3 = os.osc(freq * 8);

// Drawbar mix based on knob2 (mellow to bright)
// Mellow (low knob2): emphasize sub, fund, light upper
// Bright (high knob2): full harmonic stack
mellow = knob2;
bright = knob2 * knob2;

drawbar_mix = 
    sub * (0.5 - mellow * 0.2) +
    fund * 0.7 +
    quint_low * (0.25 + mellow * 0.15) +
    oct * (0.35 + mellow * 0.2) +
    quint * (0.15 + bright * 0.25) +
    oct2 * (0.1 + bright * 0.2) +
    third * (bright * 0.15) +
    quint_high * (bright * 0.12) +
    oct3 * (bright * 0.08);

// Normalize - more conservative to prevent summing overload
tonewheels = drawbar_mix * 0.18;

// === ORGAN ENVELOPE ===
// Hammond has nearly instant on/off with slight shaping
amp_env = gate : si.smooth(ba.tau2pole(0.003));

// === COMBINE TONE SOURCES ===
raw_organ = (tonewheels + percussion) * amp_env + key_click;

// === TUBE OVERDRIVE ===
// Hammond through a tube amp - soft saturation
drive_amount = 1.0 + (knob3 * 6.0);
overdrive(x) = ma.tanh(x * drive_amount) / max(0.7, drive_amount * 0.25);

// Pre-filter before drive (like amp input)
pre_eq = raw_organ : fi.peak_eq(3 + knob3 * 6, 800, 2);
driven = pre_eq : overdrive;

// Post-drive tone shaping
post_eq = driven : fi.lowpass(1, 6000 + (1 - knob3) * 6000);

// === ROTARY SPEAKER (Leslie) ===
leslie_speed = 0.8 + (knob4 * knob4 * 6.5);  // 0.8 - 7.3 Hz

// Horn (treble) rotation
horn_phase = os.phasor(1, leslie_speed);
horn_lfo_L = sin(horn_phase * 2 * ma.PI);
horn_lfo_R = sin((horn_phase + 0.5) * 2 * ma.PI);  // 180° out of phase

// Drum (bass) rotation - slightly slower
drum_speed = leslie_speed * 0.85;
drum_phase = os.phasor(1, drum_speed);
drum_lfo = sin(drum_phase * 2 * ma.PI);

// Amplitude modulation depths
horn_am_depth = 0.15 + (knob4 * 0.2);
drum_am_depth = 0.1;

// Split into bass and treble
bass_signal = post_eq : fi.lowpass(2, 800);
treble_signal = post_eq : fi.highpass(2, 800);

// Chorus for subtle pitch movement (fixed delays, modulated mix)
// Two fixed delay taps at slightly different times
chorus_delay1 = 0.004 * ma.SR;  // 4ms
chorus_delay2 = 0.006 * ma.SR;  // 6ms
chorus_tap1 = treble_signal : @(int(chorus_delay1));
chorus_tap2 = treble_signal : @(int(chorus_delay2));

// Crossfade between dry and taps based on LFO (no delay time modulation)
chorus_depth = knob4 * 0.3;
chorus_mix_L = 0.5 + horn_lfo_L * 0.5;  // 0-1 range
chorus_mix_R = 0.5 + horn_lfo_R * 0.5;

// Blend: dry + weighted chorus taps
treble_chorus_L = treble_signal * (1 - chorus_depth) + 
                  (chorus_tap1 * chorus_mix_L + chorus_tap2 * (1 - chorus_mix_L)) * chorus_depth;
treble_chorus_R = treble_signal * (1 - chorus_depth) + 
                  (chorus_tap1 * chorus_mix_R + chorus_tap2 * (1 - chorus_mix_R)) * chorus_depth;

// Apply amplitude modulation
treble_L = treble_chorus_L * (1 + horn_lfo_L * horn_am_depth);
treble_R = treble_chorus_R * (1 + horn_lfo_R * horn_am_depth);

bass_L = bass_signal * (1 + drum_lfo * drum_am_depth);
bass_R = bass_signal * (1 - drum_lfo * drum_am_depth);

// Recombine
leslie_L = bass_L + treble_L;
leslie_R = bass_R + treble_R;

// Leslie cabinet coloration
cabinet_L = leslie_L : fi.peak_eq(-3, 300, 1) : fi.peak_eq(2, 2500, 2);
cabinet_R = leslie_R : fi.peak_eq(-3, 300, 1) : fi.peak_eq(2, 2500, 2);

// === OUTPUT ===
out_L = cabinet_L * gain * 0.4;
out_R = cabinet_R * gain * 0.4;

soft_limit(x) = ma.tanh(x * 1.1);
process = soft_limit(out_L), soft_limit(out_R);
