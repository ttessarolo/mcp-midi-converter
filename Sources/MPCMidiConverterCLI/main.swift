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
                    let prefix = options.dryRun ? "PREVIEW" : "CREATED"
                    print("\(prefix): \(output.path)")
                    print(
                        "  tracks=\(result.report.parsedTrackCount) "
                            + "events=\(result.report.eligibleEvents) "
                            + "changed=\(result.report.changedEvents) "
                            + "fallback=\(result.report.fallbackEvents) "
                            + "silenced=\(result.report.silencedEvents)"
                    )
                } catch {
                    failed = true
                    fputs("ERROR \(input.path): \(error.localizedDescription)\n", stderr)
                }
            }
            if failed {
                exit(EXIT_FAILURE)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n\n\(Options.help)\n", stderr)
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
    Usage:
      mpc-midi-converter [options] file.mid [another.mid ...]

    Options:
      --policy fallback|silence|keep   Handle unavailable GM instruments
      --channels 10|all               GM channel 10 (default) or all channels
      --profile-file profile.json     Load an external mapping profile
      --no-poly-pressure              Do not remap Polyphonic Key Pressure
      --overwrite                     Replace an existing -mpc output
      --dry-run                       Analyze without writing
      --list-profiles                 List bundled profiles
      -h, --help                      Show this help
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
            "No MIDI input files were provided."
        case let .missingValue(option):
            "Missing value for \(option)."
        case let .invalidPolicy(value):
            "Invalid policy: \(value)."
        case let .invalidChannels(value):
            "Invalid channel selection: \(value). Use 10 or all."
        case let .unknownOption(option):
            "Unknown option: \(option)."
        }
    }
}
