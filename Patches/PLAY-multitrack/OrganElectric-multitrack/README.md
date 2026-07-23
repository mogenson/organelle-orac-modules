# PLAY-multitrack v1.1

PLAY-multitrack is an unofficial multitrack version of the wonderful Critter & Guitari PLAY patches for Organelle.

It keeps the sound character of the original PLAY instruments untouched and adds a four-track sequencer/looper workflow, a track mixer, parameter automation, bounce functions, sequence chaining, audio capture, and punch-in effects.

## Updates

**v1.1 – 2026-05-22:**

- added automation tracks for synth parameters and mixer levels 
- added Punch FX hold option
- fixed unnecessary double note-offs in sequencer data
- updated README, documented previously unmentioned track clearing

## Included patches

| Patch | Sound character |
|---|---|
| **CZ-multitrack** | Casio CZ-style phase distortion; plucky 80s digital tones. |
| **Cini-multitrack** | Ambient pad synth with swell, tone shaping, shimmer, and space. |
| **Colossus-multitrack** | Electric-piano-like synth voice with envelope, tone, pitch, and space controls. |
| **Flutetine-multitrack** | Soft tine/flute hybrid with bite, tremolo, and space. |
| **LeadHQ-multitrack** | Bright lead synth with decay, drive, brightness, and chorus character. |
| **OrganElectric-multitrack** | Electric organ voice with percussion, drawbars, drive, and rotary-style motion. |
| **OrganSpecial-multitrack** | Large organ voice with swell, brightness, vibrato, and cathedral-style space. |
| **Reeds-multitrack** | Reed-organ / harmonium-like voice with air, brightness, pulse, and room. |

## Credits and disclaimer

[The original PLAY patches](https://www.critterandguitari.com/organelle-patches/play---8-patch-set) were created by Critter & Guitari.

PLAY-multitrack is an unofficial derivative.

The multitrack patches were 100% "vibe-coded". As C&G wrote in the Organelle Programming Guide, OS 5's new Web Editor works well for LLM use. I asked the chatbot to make certain changes, and it did. There was a lot of back and forth, copy and paste. While not everything worked on the first try, eventually the LLM found solutions. For me personally, it's exciting to suddenly be able to have an instrument created according to my specifications. But the entire undertaking is, I guess, ethically questionable. I receive desired functions without having a real understanding of their architecture. Furthermore, the LLM used here is not free software, but intransparent technology in the hands of oligarchs who serve the war industry. But anyway…

## Installation

Copy the `.zip` file to your Organelle patches folder and install it from Organelle. Patches are installed into `/PLAY-multitrack/`.

## Presets

Presets are normal PLAY-style presets with additional multitrack data.

A preset contains:

- synth parameter values
- track levels
- BPM
- loop length (determined by Track 1)
- recorded note/MIDI events
- metronome setting
- selected track
- velocity mode
- automation track data

**New Preset**: To start from an empty state, select **Preset 0**.

## Saving

The Save button works differently from the original PLAY patches:

- **Short press Save/Copy**: overwrite the current preset after confirmation by pressing the same button again
- **Hold Save/Copy**: copy / save as a new preset after confirmation

Release Aux during confirmation to cancel.

New notes, loop changes, mixer changes, playlist results, etc. are not automatically stored. If you switch presets without saving, unsaved changes are discarded.

There is no artificial sequencer event limit in this build. Very large presets are possible, but they will eventually cause performance issues.

## Tracks & Display

PLAY-multitrack has four sequencer tracks.

Activate a track from **Aux Menu Page 2**.

Track status indicators:

- the selected track is shown inverted in the status display
- only the selected track records new notes
- a dot next to a track number means the track contains note material
- two dots next to a track number mean the track contains automation
- a crossed-out track number means the track is muted in the mixer
- the progress bar on the right shows where you are in the current loop

## Clear a track

To clear one of the four tracks, hold a track button on **Aux Menu Page 2** and confirm. Track 1 uses a longer hold for clear, because a shorter hold is reserved for *Bounce All To T1* (see below).

## Recording, Overdub, Undo, Redo

Typical workflow for a new preset:

1. Set metronome, BPM, and arpeggiator.
2. `Arm` recording.
3. `Play` notes.
4. Stop.
5. Select a different track.
6. Select `Over`. Overdub is active each loop cycle until you press `Stop/Play`.
7. `Undo` the last overdub. If you change your mind, `Redo` it. To do this, hold the button until the action is confirmed.

Unsaved recording, overdub, undo/redo, loop-length, and mixer settings are lost when changing presets unless the preset is saved.

## Footswitch

As an alternative to the Aux-menu shortcuts, you can use a footswitch. It works similarly to a classic live-looping pedal.

- **Press**: Play/Stop
- **Hold**: Overdub
- **Long hold**: Undo/Redo

## Bounce

Bounce moves and combines track material.

To bounce one track into another:

1. Hold the target track.
2. Press the source track.
3. Confirm the bounce.

To bounce everything directly to Track 1:

1. Hold Track 1.
2. Confirm **Bounce All? To T1**.

Bounce changes are not permanent until you save the preset.

## Automation Tracks

A track can record either note events or automation data.

You can automate the four synth parameters as well as the mixer levels.

- To create an automation track, select an empty track, press `Arm` (or `Over` if other tracks exist), and move one of the four synth knobs or a mixer level instead of playing notes. The track will record those movements.
- In Mixer view, automation tracks show a knob icon. The bottom label shows `on` or `off`. Turn the automation track's mixer knob to the right of center to switch automation on, or to the left of center to switch it off. You can only toggle on/off, when not in recording mode.
- You can record up to four automation tracks. Only one automation track can be on at a time; switching one on turns the others off (see Colossus preset as an example).
- Automation tracks can be overdubbed. Only the knobs or mixer levels touched during the loop pass are replaced; untouched parameters stay unchanged.

Automation also affects MIDI out & Export.

Note: Automation tracks cannot be bounced. When you chain presets with the Playlist Builder, automation tracks are handled as empty tracks.

## Loop length

Use the Aux menu commands:

- **Loop x2**: double the loop length
- **Loop /2**: halve the loop length

Press the same button to confirm the action.

Loop length changes are part of the current preset state. Save/Copy the preset if you want to keep them.

## Metronome

The metronome has several styles. Use the metronome menu entry to cycle through them. Entries marked with `!` are louder variants.

The meter options `3/4`, `4/4`, and `5/4` use a higher beep on the first beat and lower beeps for the remaining beats of the bar. Punch FX will adapt to the meter.

Long-press the metronome entry to quickly turn the click off.

The metronome setting is saved in the preset.

## Velocity

Velocity mode determines how note velocity is handled. Available modes:

- `pp` pianissimo
- `p` piano
- `Velocity` standard incoming velocity
- `f` forte
- `ff` fortissimo / MIDI value 127

The velocity mode is saved in the preset.

## Playlist Builder

The Playlist Builder can chain sequences from different presets into a longer song-like loop.

Long-press **Play/List** to enter the Playlist Builder.

Controls:

- **Encoder**: select a preset
- **C# / Cis**: add the selected preset to the playlist
- **D# / Dis**: remove the last playlist entry
- **Aux short press**: play the temporary playlist
- **Aux hold**: save the playlist directly as a new preset

The first preset in the playlist provides BPM, synth knob values, track levels, global settings.
Later presets provide only their recorded note/MIDI events.

The playlist is combined into one temporary loop. When a temporary playlist is playing, the main display shows `List`. The normal Play/Stop command starts and stops that temporary playlist. You can save it later as a normal preset via the Save workflow.

As an example, Preset 10 in CZ-multitrack was built by chaining presets 6, 7, 8, and 9.

## Punch FX

Open the Punch FX page from the Aux menu (`Aux` + double-click `high B`). The Punch FX page stays open until Aux is pressed again.

- Short-press an effect for a timed punch-in. Most effects start on the next beat (Freeze: immediately).
- Press an effect repeatedly to extend its duration.
- Hold an effect button for about 0.3 seconds to latch it on. Press it again to turn it off. Latched effects are marked with `+`.
- The encoder controls BPM while on the Punch FX page.
- The four knobs control the synth parameters.
- Combine some or all effects!

## Capture

Capture records the Organelle output as you hear it, including live playing, sequenced tracks, mixer levels, Punch FX.

Capture records the raw output signal without normalization or post-processing. The Volume knob has no effect on the gain.

Workflow:

1. Arm Capture in the Aux menu.
2. The LED blinks cyan.
3. Press Play to start the sequence.
4. The display shows `R E C`. The LED turns solid cyan.
5. Press Stop to finish recording.
6. A `.wav` file is saved to the `/Capture` folder.

If a USB stick is detected, the recording is saved there. Otherwise it is saved on the SD card.
Make sure to press `Reload` from Organelle's Storage menu after inserting a USB stick.

## MIDI out & Export

Like the vanilla patches, PLAY-multitrack sends out MIDI. Use the mixer to control the outgoing MIDI velocity of the four tracks.

To **export** the current preset's MIDI data, **hold Capture** for one second, then confirm `Export MIDI?` by pressing Capture again. A Standard MIDI File (`.mid`) is saved to USB if available, otherwise to the SD card. The MIDI export writes the four sequencer tracks as separate MIDI tracks and includes BPM and the selected metronome time signature.

## Compatibility

PLAY-multitrack patches can load presets that were saved on vanilla PLAY. You can then add more tracks to your recording. Vanilla patches won't load multitrack presets.

## Performance notes

PLAY-multitrack uses multiple Pure Data processes:

- **Main patch**: user interface, sequencer, presets, mixer, voice allocation
- **Synth Core A**: voices 1–4
- **Synth Core B**: voices 5–8
- **Punch FX Core**: punch-in effects

This helps distribute the workload on multicore Organelle systems.

## Optional 12-Voice Polyphony

Like the C&G original, these patches are 8-voice polyphonic by default.

If you need more voices, you can apply the optional 12-voice mod by replacing three files. The replacement files are included in the `12-Voice-Polyphony-Mod` folder inside `CZ-multitrack`. Copy the three files from that folder into any of the eight patch folders and overwrite the existing files.

On my Organelle M, the 12-voice version produced a higher CPU load and increased the core temperature by around 3 °C in the heaviest patch, OrganElectric. This was not critical in testing — OrganElectric settled around 60 °C and ran without throttling — but more CPU load and heat mean higher power usage.

Since 8 voices are enough in most cases, I have kept 8-voice polyphony as the default.

## License

This patch is licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).

You are free to share and adapt this work for non-commercial purposes, with attribution, under the same license.

## Have fun!

Thanks to Critter & Guitari for Organelle and the new OS.


