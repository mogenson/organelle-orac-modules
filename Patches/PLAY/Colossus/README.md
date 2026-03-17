# Colossus

**Character:** Classic electric piano with tone, reverb, and pitch control.

| Knob | Parameter | Range |
|------|-----------|-------|
| knob1 | Envelope | Decay/release time |
| knob2 | Tone | Brightness/bark amount |
| knob3 | Pitch | Pitch scaling (0 to full) |
| knob4 | Space | Reverb depth |

**Oscillators:** Sine fundamental + harmonics + inharmonic bell + noise bark

**Notable:** Bark envelope for attack brightness, subtle tremolo


## Operation

### Shift Button Controls

Hold **Aux** button to access the operation menu. Black keys select functions:

| Key | Function |
|-----|----------|
| C# | Play/Stop |
| D# | Arm Recording |
| F# | Previous Preset |
| G# | Save Preset |
| A# | Next Preset |
| C#+ | Octave Down |
| D#+ | Octave Up |
| F#+ | Latch Toggle |
| G#+ | Metronome |
| A#+ | Delete Preset |

The 14 white keys select different arppegio patterns. The first key is no pattern.

### BPM

Hold the **Aux** button while turning the encoder to adjust BPM (20-250). If you are connected to a network and a LINK session is present the Organelle will connect automatically.

### Recording a Sequence

1. Press Arm (shift + D#) - LED turns purple
2. Play notes and / or turn knobs - recording starts on first note or knob movement, LED turns red
3. Press Aux to stop recording - playback begins, LED turns green

---

## MIDI

Use the system MIDI Setup menu to select MIDI channel for note and CC messages.

**MIDI CC message mapping:**

| Control | CC |
|---------|-----|
| knob1 | 21 |
| knob2 | 22 |
| knob3 | 23 |
| knob4 | 24 |

---

## Info

For more information, see the [Organelle S2 Manual](https://critterandguitari.github.io/cg-docs/Organelle/og_s2/).

---

## License

This patch is licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).

You are free to share and adapt this work for non-commercial purposes, with attribution, under the same license.
