# GM to Akai MPC BFD Pop Kit 113 mapping

Profile: `akai-mpc-bfd-pop-113`.

Verified source: `Acoustic-Kit-BFD Pop Kit 113.xpm`, saved by MPC Standalone
3.9.1.2.

The destination notes are the pad notes assigned in the source Drum Program.
The profile does not modify the MPC program or its samples.

| GM | GM instrument | MPC | Kit sound | Type |
|---:|---|---:|---|---|
| 35 | Acoustic Bass Drum | 36 | Kick | primary |
| 36 | Bass Drum 1 | 36 | Kick | primary |
| 37 | Side Stick | 42 | Snare Side Stick | primary |
| 38 | Acoustic Snare | 37 | Snare Hit | primary |
| 39 | Hand Clap | 41 | Snare Rim Shot | fallback |
| 40 | Electric Snare | 40 | Snare Alt Hit | fallback |
| 41 | Low Floor Tom | 44 | Floor Tom | primary |
| 42 | Closed Hi-Hat | 38 | Closed Hat | primary |
| 43 | High Floor Tom | 44 | Floor Tom | primary (register) |
| 44 | Pedal Hi-Hat | 43 | Pedal Hat | primary |
| 45 | Low Tom | 45 | Mid Tom | primary (register) |
| 46 | Open Hi-Hat | 39 | Open Hat | primary |
| 47 | Low-Mid Tom | 45 | Mid Tom | primary (register) |
| 48 | Hi-Mid Tom | 46 | High Tom 2 | primary (register) |
| 49 | Crash Cymbal 1 | 50 | Crash 1 | primary |
| 50 | High Tom | 47 | High Tom | primary |
| 51 | Ride Cymbal 1 | 48 | Ride Bow | primary |
| 52 | Chinese Cymbal | 51 | Crash 2 | fallback |
| 53 | Ride Bell | 49 | Ride Bell | primary |
| 54 | Tambourine | 0 | empty pad | unavailable |
| 55 | Splash Cymbal | 50 | Crash 1 | fallback |
| 56 | Cowbell | 49 | Ride Bell | fallback |
| 57 | Crash Cymbal 2 | 51 | Crash 2 | primary |
| 58 | Vibra Slap | 0 | empty pad | unavailable |
| 59 | Ride Cymbal 2 | 48 | Ride Bow | primary (articulation) |
| 60 | Hi Bongo | 0 | empty pad | unavailable |
| 61 | Low Bongo | 0 | empty pad | unavailable |
| 62 | Mute Hi Conga | 0 | empty pad | unavailable |
| 63 | Open Hi Conga | 0 | empty pad | unavailable |
| 64 | Low Conga | 0 | empty pad | unavailable |
| 65 | High Timbale | 0 | empty pad | unavailable |
| 66 | Low Timbale | 0 | empty pad | unavailable |
| 67 | High Agogo | 0 | empty pad | unavailable |
| 68 | Low Agogo | 0 | empty pad | unavailable |
| 69 | Cabasa | 0 | empty pad | unavailable |
| 70 | Maracas | 0 | empty pad | unavailable |
| 71 | Short Whistle | 0 | empty pad | unavailable |
| 72 | Long Whistle | 0 | empty pad | unavailable |
| 73 | Short Guiro | 0 | empty pad | unavailable |
| 74 | Long Guiro | 0 | empty pad | unavailable |
| 75 | Claves | 0 | empty pad | unavailable |
| 76 | Hi Wood Block | 0 | empty pad | unavailable |
| 77 | Low Wood Block | 0 | empty pad | unavailable |
| 78 | Mute Cuica | 0 | empty pad | unavailable |
| 79 | Open Cuica | 0 | empty pad | unavailable |
| 80 | Mute Triangle | 0 | empty pad | unavailable |
| 81 | Open Triangle | 0 | empty pad | unavailable |

With the **primary mappings only** policy, notes 39, 40, 52, 55, and 56 also
go to silent note 0. With **keep original**, every note without an equivalent
remains unchanged; that is useful for diagnosis, but may trigger a sound other
than the intended GM instrument in this kit.

## Observed MPC layout

| MPC note | Logical pad | Articulation |
|---:|---:|---|
| 36 | 1 | Kick |
| 37 | 2 | Snare Hit |
| 38 | 3 | Closed Hat |
| 39 | 4 | Open Hat |
| 40 | 5 | Snare Alt Hit |
| 41 | 6 | Snare Rim Shot |
| 42 | 7 | Snare Side Stick |
| 43 | 8 | Pedal Hat |
| 44 | 9 | Floor Tom |
| 45 | 10 | Mid Tom |
| 46 | 11 | High Tom 2 |
| 47 | 12 | High Tom |
| 48 | 13 | Ride Bow |
| 49 | 14 | Ride Bell |
| 50 | 15 | Crash 1 |
| 51 | 16 | Crash 2 |

Every articulation in the analyzed program had eight velocity layers. Those
layers remain in the MPC Drum Program: MIDI conversion preserves event velocity
and changes only the note.
