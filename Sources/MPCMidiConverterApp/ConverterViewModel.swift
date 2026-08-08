import AppKit
import Foundation
import MPCMidiConverterCore
import UniformTypeIdentifiers

@MainActor
final class ConverterViewModel: ObservableObject {
    static let shared = ConverterViewModel()

    @Published private(set) var files: [URL] = []
    @Published var selectedProfile: TranslationProfile = .bfdPop113
    @Published var unavailablePolicy: UnavailableNotePolicy = .musicalFallback
    @Published var channelSelection: MIDIChannelSelection = .generalMIDIPercussion
    @Published var remapPolyphonicKeyPressure = true
    @Published var overwriteExisting = false
    @Published private(set) var outcomes: [FileConversionOutcome] = []
    @Published private(set) var isConverting = false
    @Published var notice: String?

    @Published private(set) var profiles: [TranslationProfile]

    private init() {
        profiles = Self.loadInstalledProfiles()
        if let defaultProfile = profiles.first(where: { $0.id == selectedProfile.id }) {
            selectedProfile = defaultProfile
        }
    }

    func addFiles(_ urls: [URL]) {
        var rejected: [String] = []
        var knownPaths = Set(files.map(\.standardizedFileURL.path))
        for url in urls {
            let normalized = url.standardizedFileURL
            let extensionLowercased = normalized.pathExtension.lowercased()
            guard extensionLowercased == "mid" || extensionLowercased == "midi" else {
                rejected.append(normalized.lastPathComponent)
                continue
            }
            if knownPaths.insert(normalized.path).inserted {
                files.append(normalized)
            }
        }
        outcomes = []
        if !rejected.isEmpty {
            notice = "Ignorati file non MIDI: \(rejected.joined(separator: ", "))."
        } else {
            notice = nil
        }
    }

    func removeFile(_ url: URL) {
        files.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        outcomes.removeAll { $0.input.standardizedFileURL == url.standardizedFileURL }
    }

    func clearFiles() {
        files.removeAll()
        outcomes.removeAll()
        notice = nil
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Scegli file MIDI General MIDI"
        panel.prompt = "Aggiungi"
        panel.allowedContentTypes = [.midi]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Importa un profilo di mapping"
        panel.prompt = "Importa"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let profile = try TranslationProfile.load(from: url)
            let storedURL = try Self.storeImportedProfile(data: Data(contentsOf: url), profile: profile)
            if let existing = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[existing] = profile
            } else {
                profiles.append(profile)
                profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            selectedProfile = profile
            outcomes = []
            notice = "Profilo installato: \(profile.name) (\(storedURL.lastPathComponent))."
        } catch {
            notice = "Profilo non valido: \(error.localizedDescription)"
        }
    }

    func convert() {
        guard !files.isEmpty, !isConverting else { return }
        isConverting = true
        outcomes = []
        notice = nil

        let inputs = files
        let overwrite = overwriteExisting
        let configuration = MIDITranslationConfiguration(
            profile: selectedProfile,
            unavailableNotePolicy: unavailablePolicy,
            channels: channelSelection,
            remapPolyphonicKeyPressure: remapPolyphonicKeyPressure
        )

        Task {
            let converted = await Task.detached(priority: .userInitiated) {
                inputs.map { input in
                    convertFile(input, configuration: configuration, overwrite: overwrite)
                }
            }.value
            outcomes = converted
            isConverting = false
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func loadInstalledProfiles() -> [TranslationProfile] {
        var profilesByID = Dictionary(
            uniqueKeysWithValues: TranslationProfile.builtIns.map { ($0.id, $0) }
        )
        guard let directory = try? profilesDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else {
            return TranslationProfile.builtIns
        }
        for file in files
            .filter({ $0.pathExtension.lowercased() == "json" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let profile = try? TranslationProfile.load(from: file) {
                profilesByID[profile.id] = profile
            }
        }
        return profilesByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func storeImportedProfile(
        data: Data,
        profile: TranslationProfile
    ) throws -> URL {
        let safeID = profile.id.map { character in
            character.isLetter || character.isNumber || "-_.".contains(character)
                ? character
                : "_"
        }
        let output = try profilesDirectory()
            .appendingPathComponent("profile-\(String(safeID))")
            .appendingPathExtension("json")
        try data.write(to: output, options: .atomic)
        return output
    }

    private static func profilesDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("MPC MIDI Converter", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

struct FileConversionOutcome: Identifiable, Sendable {
    let input: URL
    let output: URL?
    let report: MIDIConversionReport?
    let errorMessage: String?

    var id: String { input.standardizedFileURL.path }
    var succeeded: Bool { output != nil && errorMessage == nil }
}

private func convertFile(
    _ input: URL,
    configuration: MIDITranslationConfiguration,
    overwrite: Bool
) -> FileConversionOutcome {
    let hasSecurityScope = input.startAccessingSecurityScopedResource()
    defer {
        if hasSecurityScope {
            input.stopAccessingSecurityScopedResource()
        }
    }

    do {
        let data = try Data(contentsOf: input, options: .mappedIfSafe)
        let result = try StandardMIDIRewriter.rewrite(data, configuration: configuration)
        let output = try OutputFile.write(result.data, for: input, overwrite: overwrite)
        return FileConversionOutcome(
            input: input,
            output: output,
            report: result.report,
            errorMessage: nil
        )
    } catch {
        return FileConversionOutcome(
            input: input,
            output: nil,
            report: nil,
            errorMessage: error.localizedDescription
        )
    }
}
