# MPC MIDI Converter

Un piccolo droplet nativo per macOS che traduce la traccia di batteria di uno
Standard MIDI File dal mapping General MIDI alle note usate da un Drum Program
Akai MPC. Il file originale non viene modificato: l'output viene scritto nella
stessa cartella aggiungendo `-mpc` al nome.

Il primo profilo incluso è stato ricavato dal programma
`Acoustic-Kit-BFD Pop Kit 113.xpm` esportato da MPC 3.9.1.2. Non è una tabella
Akai presunta: le note dei pad sono quelle osservate nel programma reale.

## Uso sul Mac

1. Apri `dist/MPC MIDI Converter.app`.
2. Trascina uno o più file `.mid`/`.midi` nella finestra. In alternativa,
   trascinali sull'icona dell'app nel Finder o nel Dock.
3. Prima di convertire, scegli il profilo, la policy per gli strumenti mancanti
   e i canali da elaborare.
4. Premi **Converti**. Per `Brano.mid` verrà creato `Brano-mpc.mid` accanto
   all'originale.
5. Importa `Brano-mpc.mid` nella MPC e usalo con il Drum Program per cui è stato
   costruito il profilo.

La configurazione consigliata è:

- profilo `Akai MPC - BFD Pop Kit 113`;
- fallback musicali, poi silenzio;
- solo canale 10 GM;
- Polyphonic Key Pressure rimappata;
- sovrascrittura disabilitata.

Il convertitore non parte automaticamente al drop: mostra sempre le opzioni e
aspetta il comando **Converti**. Se un output esiste già, lo rifiuta finché non
si abilita esplicitamente la sovrascrittura.

## Mapping stabile e cambio kit

Il programma modifica le note nel **file MIDI**, non i sample né il Drum
Program. Dopo la conversione il brano rimane agganciato alle posizioni dei pad
del profilo selezionato.

Puoi quindi cambiare kit senza riconvertire soltanto se il nuovo Drum Program
mette kick, snare, hi-hat, tom e piatti sulle stesse note/pad del profilo. Se un
kit usa un ordine diverso, serve un suo profilo: dalla finestra premi
**Importa…** accanto al selettore del profilo. Questa separazione mantiene il
mapping deterministico e impedisce che il cambio di sample alteri il MIDI.
I profili importati vengono conservati in
`~/Library/Application Support/MPC MIDI Converter/Profiles` e ricaricati agli
avvii successivi.

Il formato dei profili è JSON. `profiles/bfd-pop-113.json` è un modello
completo:

```json
{
  "id": "identificatore-stabile",
  "name": "Nome mostrato nella app",
  "description": "Origine e versione del mapping",
  "source": "General MIDI Level 1 percussion",
  "target": "Nome del Drum Program MPC",
  "gmRange": [35, 81],
  "silentNote": 0,
  "direct": { "36": 36, "38": 37 },
  "fallback": { "39": 41 }
}
```

`direct` contiene i mapping primari verso le articolazioni realmente presenti
nel kit, incluse eventuali approssimazioni di registro dichiarate nella tabella;
`fallback` contiene sostituzioni con un'articolazione di tipo diverso.
`silentNote` deve indicare un pad realmente vuoto nel kit di destinazione. La app
valida intervalli, note MIDI 0–127, identità e mapping duplicati prima di
accettare un profilo.

La tabella completa del profilo incluso è in
[`docs/mapping-bfd-pop-113.md`](docs/mapping-bfd-pop-113.md).

## Garanzie della conversione

- legge SMF formato 0, 1 e 2;
- interpreta chunk, delta-time VLQ, running status, meta-eventi e SysEx;
- traduce i key byte di Note On/Note Off e, se richiesto, Polyphonic Key
  Pressure;
- lascia intatti tempo, velocity, durata, controller, Program Change, SysEx,
  meta-eventi, altri canali e chunk non-MTrk;
- non ricostruisce il file: lunghezze e tutti i byte non interessati restano
  identici;
- non modifica mai l'input; senza sovrascrittura crea l'output in modalità
  esclusiva, mentre con sovrascrittura usa una sostituzione atomica.

Il canale 10 è la convenzione GM per la batteria. La modalità **tutti i canali**
è destinata a file che contengono esclusivamente parti percussive.

## CLI

Il repository include anche un eseguibile da terminale:

```sh
swift run mpc-midi-converter --dry-run Brano.mid
swift run mpc-midi-converter --policy fallback --channels 10 Brano.mid
swift run mpc-midi-converter --profile-file altro-kit.json Brano.mid
```

Usa `swift run mpc-midi-converter --help` per tutte le opzioni.

## Build e verifica

Richiede macOS 13 o successivo e Xcode/Swift installato.

```sh
make test
make app
make verify
```

`make app` genera:

- `dist/MPC MIDI Converter.app`
- `dist/MPC MIDI Converter.zip`

Il bundle locale è firmato ad hoc. Per distribuire l'app a terzi fuori dal Mac
di sviluppo occorrono una firma Developer ID e la notarizzazione Apple.

Le scelte tecniche, le fonti normative e il confronto con i converter esistenti
sono documentati in [`docs/research.md`](docs/research.md).
