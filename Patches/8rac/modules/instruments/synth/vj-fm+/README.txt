vj-fm

A powerful and fully customizable 9 operator FM synth with 3 voice polyphony using phase modulation.

Each operator comes with these options:

* Page 1:
  * Volume/modulation index
  * Frequency multiplier
  * Frequency divider
  * Velocity sensitivity (toggle)
* Page 2, ADSR envelope
* Page 3, Feedback

Here are how the operators are connected:

L1M2 -> L1M1 -> L1C -> Audio out
L2M2 -> L2M1 -> L2C -> Audio out
L3M2 -> L3M1 -> L3C -> Audio out

To summarize, 3 carriers, with two operators modulating each of them in series. "L1" denotes "lane 1". "C" denotes "carrier". M1 denotes "modulator, with depth 1". That results in 9 * 3 = 27 pages of parameters. A bit menu divey but extremely powerful and customizable.

By default, only L1C has parameters to output audio. To get started, try turning the Mod Idx of L1M1 and mess with the frequency multiplier and divider.

For the adventurous, the Pure Data source can be modified to configure other algorithms.

LICENSE: GPLv3

Backstory:

Started learning Pure Data a week ago, ended by becoming obsessed and spent two entire days learning and creating this lovely patch! If you look at the code, appreciate any tips.

