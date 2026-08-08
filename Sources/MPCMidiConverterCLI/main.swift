import Darwin
import Foundation
import MPCMidiConverterCore

@main
enum MPCMidiConverterCLI {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments.dropFirst())
            if options.showHelp {
                print(Options.help)
                return
            }
            if options.listProfiles {
                for profile in TranslationProfile.builtIns {
                    print("\(profile.id)\t\(profile.name)")
                }
                return
            }
            guard !options.inputs.isEmpty else {
                throw CLIError.noInputFiles
            }

            let profile = try options.profileFile.map(TranslationProfile.load(from:))
                ?? TranslationProfile.bfdPop113
            let configuration = MIDITranslationConfiguration(
                profile: profile,
                unavailableNotePolicy: options.policy,
                channels: options.channels,
                remapPolyphonicKeyPressure: options.remapPolyphonicKeyPressure
            )

            var failed = false
            for input in options.inputs {
                do {
                    let inputData = try Data(contentsOf: input)
                    let result = try StandardMIDIRewriter.rewrite(
                        inputData,
                        configuration: configuration
                    )
                    let output = try OutputFile.url(for: input)
                    if !options.dryRun {
                        _ = try OutputFile.write(
                            result.data,
                            for: input,
                            overwrite: options.overwrite
                        )
                    }
                    let prefix = options.dryRun ? "ANTEPRIMA" : "CREATO"
                    print("\(prefix): \(output.path)")
                    print(
                        "  tracce=\(result.report.parsedTrackCount) "
                            + "eventi=\(result.report.eligibleEvents) "
                            + "modificati=\(result.report.changedEvents) "
                            + "fallback=\(result.report.fallbackEvents) "
                            + "silenziosi=\(result.report.silencedEvents)"
                    )
                } catch {
                    failed = true
                    fputs("ERRORE \(input.path): \(error.localizedDescription)\n", stderr)
                }
            }
            if failed {
                exit(EXIT_FAILURE)
            }
        } catch {
            fputs("Errore: \(error.localizedDescription)\n\n\(Options.help)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

private struct Options {
    var inputs: [URL] = []
    var profileFile: URL?
    var policy: UnavailableNotePolicy = .musicalFallback
    var channels: MIDIChannelSelection = .generalMIDIPercussion
    var remapPolyphonicKeyPressure = true
    var overwrite = false
    var dryRun = false
    var showHelp = false
    var listProfiles = false

    static func parse<S: Sequence>(_ arguments: S) throws -> Options where S.Element == String {
        var options = Options()
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help":
                options.showHelp = true
            case "--list-profiles":
                options.listProfiles = true
            case "--profile-file":
                guard let path = iterator.next() else { throw CLIError.missingValue(argument) }
                options.profileFile = URL(fileURLWithPath: path)
            case "--policy":
                guard let value = iterator.next() else { throw CLIError.missingValue(argument) }
                switch value {
                case "fallback": options.policy = .musicalFallback
                case "silence": options.policy = .silence
                case "keep": options.policy = .keepOriginal
                default: throw CLIError.invalidPolicy(value)
                }
            case "--channels":
                guard let value = iterator.next() else { throw CLIError.missingValue(argument) }
                switch value {
                case "10": options.channels = .generalMIDIPercussion
                case "all": options.channels = .allChannels
                default: throw CLIError.invalidChannels(value)
                }
            case "--no-poly-pressure":
                options.remapPolyphonicKeyPressure = false
            case "--overwrite":
                options.overwrite = true
            case "--dry-run":
                options.dryRun = true
            default:
                if argument.hasPrefix("-") {
                    throw CLIError.unknownOption(argument)
                }
                options.inputs.append(URL(fileURLWithPath: argument))
            }
        }
        return options
    }

    static let help = """
    Uso:
      mpc-midi-converter [opzioni] file.mid [altro.mid ...]

    Opzioni:
      --policy fallback|silence|keep   Gestione strumenti GM non disponibili
      --channels 10|all               Canale 10 GM (default) o tutti i canali
      --profile-file profilo.json     Carica un profilo esterno
      --no-poly-pressure              Non rimappare Polyphonic Key Pressure
      --overwrite                     Sovrascrive un output -mpc già esistente
      --dry-run                       Analizza senza scrivere
      --list-profiles                 Elenca i profili inclusi
      -h, --help                      Mostra questo aiuto
    """
}

private enum CLIError: LocalizedError {
    case noInputFiles
    case missingValue(String)
    case invalidPolicy(String)
    case invalidChannels(String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .noInputFiles:
            "Nessun file MIDI indicato."
        case let .missingValue(option):
            "Manca il valore per \(option)."
        case let .invalidPolicy(value):
            "Policy non valida: \(value)."
        case let .invalidChannels(value):
            "Canali non validi: \(value). Usa 10 oppure all."
        case let .unknownOption(option):
            "Opzione sconosciuta: \(option)."
        }
    }
}
