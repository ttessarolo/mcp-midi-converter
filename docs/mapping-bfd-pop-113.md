# Mapping GM → Akai MPC BFD Pop Kit 113

Profilo: `akai-mpc-bfd-pop-113`.

Sorgente verificata: `Acoustic-Kit-BFD Pop Kit 113.xpm`, salvato da MPC
Standalone 3.9.1.2.

Le note di destinazione sono le note assegnate ai pad nel Drum Program sorgente.
Il profilo non modifica il programma MPC né i suoi sample.

| GM | Strumento GM | MPC | Suono nel kit | Tipo |
|---:|---|---:|---|---|
| 35 | Acoustic Bass Drum | 36 | Kick | primaria |
| 36 | Bass Drum 1 | 36 | Kick | primaria |
| 37 | Side Stick | 42 | Snare Side Stick | primaria |
| 38 | Acoustic Snare | 37 | Snare Hit | primaria |
| 39 | Hand Clap | 41 | Snare Rim Shot | fallback |
| 40 | Electric Snare | 40 | Snare Alt Hit | fallback |
| 41 | Low Floor Tom | 44 | Floor Tom | primaria |
| 42 | Closed Hi-Hat | 38 | Closed Hat | primaria |
| 43 | High Floor Tom | 44 | Floor Tom | primaria (registro) |
| 44 | Pedal Hi-Hat | 43 | Pedal Hat | primaria |
| 45 | Low Tom | 45 | Mid Tom | primaria (registro) |
| 46 | Open Hi-Hat | 39 | Open Hat | primaria |
| 47 | Low-Mid Tom | 45 | Mid Tom | primaria (registro) |
| 48 | Hi-Mid Tom | 46 | High Tom 2 | primaria (registro) |
| 49 | Crash Cymbal 1 | 50 | Crash 1 | primaria |
| 50 | High Tom | 47 | High Tom | primaria |
| 51 | Ride Cymbal 1 | 48 | Ride Bow | primaria |
| 52 | Chinese Cymbal | 51 | Crash 2 | fallback |
| 53 | Ride Bell | 49 | Ride Bell | primaria |
| 54 | Tambourine | 0 | pad vuoto | non disponibile |
| 55 | Splash Cymbal | 50 | Crash 1 | fallback |
| 56 | Cowbell | 49 | Ride Bell | fallback |
| 57 | Crash Cymbal 2 | 51 | Crash 2 | primaria |
| 58 | Vibra Slap | 0 | pad vuoto | non disponibile |
| 59 | Ride Cymbal 2 | 48 | Ride Bow | primaria (articolazione) |
| 60 | Hi Bongo | 0 | pad vuoto | non disponibile |
| 61 | Low Bongo | 0 | pad vuoto | non disponibile |
| 62 | Mute Hi Conga | 0 | pad vuoto | non disponibile |
| 63 | Open Hi Conga | 0 | pad vuoto | non disponibile |
| 64 | Low Conga | 0 | pad vuoto | non disponibile |
| 65 | High Timbale | 0 | pad vuoto | non disponibile |
| 66 | Low Timbale | 0 | pad vuoto | non disponibile |
| 67 | High Agogo | 0 | pad vuoto | non disponibile |
| 68 | Low Agogo | 0 | pad vuoto | non disponibile |
| 69 | Cabasa | 0 | pad vuoto | non disponibile |
| 70 | Maracas | 0 | pad vuoto | non disponibile |
| 71 | Short Whistle | 0 | pad vuoto | non disponibile |
| 72 | Long Whistle | 0 | pad vuoto | non disponibile |
| 73 | Short Guiro | 0 | pad vuoto | non disponibile |
| 74 | Long Guiro | 0 | pad vuoto | non disponibile |
| 75 | Claves | 0 | pad vuoto | non disponibile |
| 76 | Hi Wood Block | 0 | pad vuoto | non disponibile |
| 77 | Low Wood Block | 0 | pad vuoto | non disponibile |
| 78 | Mute Cuica | 0 | pad vuoto | non disponibile |
| 79 | Open Cuica | 0 | pad vuoto | non disponibile |
| 80 | Mute Triangle | 0 | pad vuoto | non disponibile |
| 81 | Open Triangle | 0 | pad vuoto | non disponibile |

Con la policy **solo mapping primari**, anche 39, 40, 52, 55 e 56 vanno alla
nota silenziosa 0. Con **mantieni originali**, ogni nota senza equivalenza
resta invariata: è utile per diagnosi, ma su questo kit può attivare un suono
diverso da quello GM atteso.

## Layout MPC osservato

| Nota MPC | Pad logico | Articolazione |
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

Ogni articolazione del programma analizzato aveva otto velocity layer. Questi
layer restano nel Drum Program MPC: la conversione MIDI conserva integralmente
la velocity degli eventi e cambia soltanto la nota.
