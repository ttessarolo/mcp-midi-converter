# Ricerca e decisioni tecniche

Ricerca verificata il 2026-08-08.

## Specifiche normative

- La MIDI Association pubblica la specifica ufficiale
  [Standard MIDI Files 1.0 (RP-001)](https://midi.org/standard-midi-files-specification).
  Il parser segue la struttura `MThd`/`MTrk`, i delta-time a lunghezza
  variabile, il running status, i meta-eventi e gli eventi SysEx.
- Il mapping di partenza è
  [General MIDI System Level 1 (RP-003)](https://midi.org/general-midi-level-1):
  percussioni 35–81 sul canale MIDI 10.
- La MIDI Association chiarisce anche quali campi SMF usano
  [Variable Length Quantities](https://midi.org/community/midi-specifications/which-items-can-be-variable-length):
  delta-time, lunghezze SysEx e lunghezze dei meta-eventi.

Il converter non decodifica e riserializza l'intero brano. Dopo avere validato
i confini degli eventi, sostituisce in-place soltanto il byte della key. Questo
mantiene identici dimensione del file, lunghezze dei chunk, timing, running
status e ogni dato non interessato.

## Integrazione macOS

- Il Finder consegna i documenti aperti/trascinati sull'icona attraverso
  [`NSApplicationDelegate`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate).
- Il tipo di sistema usato è
  [`UTType.midi`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/midi),
  dichiarato nel bundle come `public.midi-audio` tramite
  [`CFBundleDocumentTypes`](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html).
- Il drop nella finestra usa
  [`onDrop`](https://developer.apple.com/documentation/swiftui/view/ondrop%28of%3Aistargeted%3Aperform%3A%29)
  per conservare compatibilità con macOS 13.
- Il bundle locale usa una
  [firma ad hoc](https://developer.apple.com/documentation/security/seccodesignatureflags/adhoc).
  La [notarizzazione](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
  richiede invece una distribuzione firmata con Developer ID.

L'app locale non è sandboxed: deve poter creare l'output accanto a un documento
aperto dal Finder, anche su volumi esterni. Non usa rete e non scrive altrove.

## Soluzioni esistenti valutate

| Prodotto | Cosa offre | Perché non copre questo caso |
|---|---|---|
| [DrumRemap](https://github.com/marty-615/drum-remap) | Remapping web di drum MIDI, preset GM e di alcuni plugin | Nessun profilo MPC/XPM; licenza non dichiarata nel repository alla data della ricerca |
| [Drum Mapper](https://github.com/insomnimus/drum-mapper) | CLI e plugin VST3/CLAP open source, mapping custom | Non dichiara supporto MPC/XPM né preservazione byte-per-byte degli SMF |
| [MidiRemap](https://www.midiremap.com/) | Servizio/plugin commerciale per mappe custom | Non dichiara un profilo Akai MPC né il modello di output richiesto |
| [ConvertWithMoss](https://www.mossgrabers.de/Software/ConvertWithMoss/ConvertWithMoss.html) | Conversione fra formati di multisample, incluso Akai MPC | Converte strumenti/sample; non è documentato come remapper GM→MPC di Standard MIDI File |

Non è stata trovata una soluzione esistente che combini simultaneamente:

1. mapping GM percussivo verso le note di uno specifico Drum Program MPC;
2. output fratello con suffisso `-mpc`;
3. scelta della policy prima della conversione;
4. trasformazione SMF byte-preserving;
5. droplet nativo macOS.

## Confine importante

Non esiste un mapping semantico universale per ogni Drum Program MPC: una nota
identifica un pad, mentre il sample assegnato a quel pad dipende dal programma.
Per questo il converter usa profili espliciti e versionati. Kit che condividono
lo stesso layout di articolazioni possono condividere il profilo; kit con pad
diversi richiedono un profilo diverso.
