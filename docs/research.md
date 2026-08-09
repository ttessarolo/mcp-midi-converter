# Research and technical decisions

Research last checked: 2026-08-08.

## Normative sources

- The MIDI Association publishes [Standard MIDI Files 1.0 (RP-001)](https://midi.org/standard-midi-files-specification).
  The parser follows the `MThd`/`MTrk` structure, variable-length delta-times,
  running status, meta events, and SysEx events.
- The source mapping is [General MIDI System Level 1 (RP-003)](https://midi.org/general-midi-level-1):
  percussion notes 35–81 on MIDI channel 10.
- The MIDI Association also identifies the SMF fields that use [Variable Length
  Quantities](https://midi.org/community/midi-specifications/which-items-can-be-variable-length):
  delta-times, SysEx lengths, and meta-event lengths.

The converter does not decode and reserialize a song. After validating event
boundaries, it replaces only the key byte in place. This preserves file size,
chunk lengths, timing, running status, and every unrelated byte.
After every track declared by the MIDI header has been parsed, trailing ASCII
tabs, spaces, and line endings are tolerated and preserved byte for byte. Any
other incomplete or unknown trailing data still fails closed.

## macOS integration

- Finder delivers documents opened or dropped on the app icon through
  [`NSApplicationDelegate`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate).
- The system type is
  [`UTType.midi`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/midi),
  declared as `public.midi-audio` through
  [`CFBundleDocumentTypes`](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html).
- The window uses SwiftUI
  [`onDrop`](https://developer.apple.com/documentation/swiftui/view/ondrop%28of%3Aistargeted%3Aperform%3A%29)
  to retain macOS 13 compatibility.
- The local bundle uses an [ad-hoc signature](https://developer.apple.com/documentation/security/seccodesignatureflags/adhoc).
  [Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
  instead requires Developer ID signing for distribution.

The local app is not sandboxed because it must create output beside a Finder-opened
document, including on external volumes. It writes converted MIDI beside the
input and explicitly installed profiles under Application Support. It never
uploads files automatically. At the user's explicit command it can open a
prefilled GitHub issue in the default browser; the browser displays the editable
draft and the user still decides whether to submit it.

## MPC XPM evidence and boundaries

Akai documents that MPC 3 standalone saves Drum Programs and Keygroups as
`.xpm` files with associated samples, while MPC 3 desktop saves Drum tracks as
`.xtd` and Keygroups as `.xty` with a `TrackData` folder. See Akai's
[MPC 3 save/load article](https://inmusicsupport.freshdesk.com/en/support/solutions/articles/69000878402-akai-pro-mpc-series-saving-loading-drum-and-keygroups-in-mpc-desktop-standalone).
Akai also documents that every drum pad has a MIDI note and that the map is
specific to the Drum Program: [Edit Pad Note Map](https://support.akaipro.com/en/support/solutions/articles/69000880963-akai-pro-mpc-series-why-do-my-drum-samples-disappear-when-i-press-certain-keys-).

Akai publishes the XPM workflow but no public XPM schema or programming API.
An XPM and sample names can therefore provide evidence of pad notes, references,
and layers, but they do not provide a normative semantic label such as
“Acoustic Snare” or “Low Tom.” Sample-name classification is a review aid, not
an automatic guarantee. A proposed mapping must distinguish primary matches,
musical fallbacks, and intentionally silent notes.

The importer is read-only and recognizes the MPC 3 gzip/ACVS JSON container
observed in standalone exports as well as the older `MPCVObject` XML layout. It
requires a complete 128-note pad map, unique MIDI notes, valid velocity ranges,
and at least one populated pad. Unknown or malformed layouts fail closed. The
64 MiB compressed and decompressed limits bound parser resource use. Sample
references are checked only as flat, non-symlink files within the XPM directory
and its sibling `_[ProgramData]` directory; absolute, nested, parent-traversing,
and symlink references are never followed.

[ConvertWithMoss's MPC detector](https://github.com/git-moss/ConvertWithMoss/blob/main/src/main/java/de/mossgrabers/convertwithmoss/format/akai/mpc/MPCModernDetector.java)
was used as an independent interoperability reference for identifying the two
container families and legacy XML element names. Its LGPLv3 implementation is
not linked, copied, or shipped by this project.

## Existing solutions considered

| Product | What it offers | Why it does not cover this case |
|---|---|---|
| [DrumRemap](https://github.com/marty-615/drum-remap) | Web drum-MIDI remapping with GM and selected plug-in presets | No MPC/XPM profile; no declared repository license at the time of research |
| [Drum Mapper](https://github.com/insomnimus/drum-mapper) | Open-source CLI and VST3/CLAP plug-in with custom mappings | Does not claim MPC/XPM support or byte-preserving SMF output |
| [MidiRemap](https://www.midiremap.com/) | Commercial service/plug-in for custom maps | Does not declare an Akai MPC profile or the required output model |
| [ConvertWithMoss](https://www.mossgrabers.de/Software/ConvertWithMoss/ConvertWithMoss.html) | Open-source (LGPLv3) multisample converter that documents modern Akai MPC/XPM support | Converts instruments and samples; it is not documented as a GM-to-MPC Standard MIDI File remapper |

No existing solution was found that combines all of the following:

1. a GM percussion mapping to the notes of one specific MPC Drum Program;
2. a sibling output file with the `-mpc` suffix;
3. policy selection before conversion;
4. byte-preserving SMF transformation; and
5. a native macOS droplet.

## Important boundary

There is no universal semantic mapping for every MPC Drum Program: a MIDI note
identifies a pad, while the sample and articulation assigned to that pad belong
to that program. The converter therefore uses explicit, versioned profiles. Kits
with the same articulation layout may share a profile; a different pad layout
requires a different profile.
