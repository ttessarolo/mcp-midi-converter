import AppKit
import MPCMidiConverterCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: ConverterViewModel
    @State private var dropIsTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            dropZone
            options
            actionBar
            results
        }
        .padding(24)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("MPC MIDI Converter")
                    .font(.title2.bold())
                Text("General MIDI → mapping del kit Akai MPC")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            if model.files.isEmpty {
                Image(systemName: "music.note.list")
                    .font(.system(size: 34))
                    .foregroundStyle(dropIsTargeted ? .blue : .secondary)
                Text("Trascina qui uno o più file .mid/.midi")
                    .font(.headline)
                Text("Puoi anche trascinarli direttamente sull'icona dell'app nel Finder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Scegli file…") {
                    model.chooseFiles()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.files, id: \.standardizedFileURL) { file in
                            HStack {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.lastPathComponent)
                                        .lineLimit(1)
                                    Text("Output: \(outputName(for: file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    model.removeFile(file)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Rimuovi")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        }
                    }
                }
                .frame(maxHeight: 130)

                HStack {
                    Button("Aggiungi…") { model.chooseFiles() }
                    Button("Rimuovi tutti") { model.clearFiles() }
                    Spacer()
                    Text("\(model.files.count) file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 125)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(dropIsTargeted ? Color.blue.opacity(0.10) : Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    dropIsTargeted ? Color.blue : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [7])
                )
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropIsTargeted) { providers in
            loadDroppedFiles(providers)
        }
    }

    private var options: some View {
        GroupBox("Opzioni di traduzione") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Profilo di destinazione")
                    HStack {
                        Picker("", selection: $model.selectedProfile) {
                            ForEach(model.profiles) { profile in
                                Text(profile.name).tag(profile)
                            }
                        }
                        .labelsHidden()
                        Button("Importa…") { model.importProfile() }
                            .help("Importa un profilo di mapping JSON per un altro kit")
                    }
                }
                GridRow {
                    Text("Strumenti non disponibili")
                    Picker("", selection: $model.unavailablePolicy) {
                        ForEach(UnavailableNotePolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Canali da convertire")
                    Picker("", selection: $model.channelSelection) {
                        ForEach(MIDIChannelSelection.allCases) { channels in
                            Text(channels.title).tag(channels)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(.top, 4)

            Text(model.unavailablePolicy.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            HStack(spacing: 18) {
                Toggle("Rimappa Polyphonic Key Pressure", isOn: $model.remapPolyphonicKeyPressure)
                Toggle("Sovrascrivi output esistenti", isOn: $model.overwriteExisting)
            }
            .padding(.top, 8)

            DisclosureGroup("Anteprima del profilo") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selectedProfile.description)
                    Text("\(model.selectedProfile.direct.count) mapping primari, \(model.selectedProfile.fallback.count) fallback dichiarati, note GM \(model.selectedProfile.gmRange.lowerBound)–\(model.selectedProfile.gmRange.upperBound).")
                    Text("I dati MIDI non interessati restano byte-per-byte identici.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            }
            .padding(.top, 8)
        }
    }

    private var actionBar: some View {
        HStack {
            Text("L'output viene scritto accanto all'originale con suffisso -mpc.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isConverting {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Converti") {
                model.convert()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(model.files.isEmpty || model.isConverting)
        }
    }

    @ViewBuilder
    private var results: some View {
        if !model.outcomes.isEmpty {
            GroupBox("Risultati") {
                VStack(spacing: 8) {
                    ForEach(model.outcomes) { outcome in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(outcome.succeeded ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(outcome.input.lastPathComponent)
                                    .fontWeight(.medium)
                                if let report = outcome.report, let output = outcome.output {
                                    Text("Creato \(output.lastPathComponent) · \(report.changedEvents) eventi modificati, \(report.fallbackEvents) fallback, \(report.silencedEvents) silenziati")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let message = outcome.errorMessage {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            if let output = outcome.output {
                                Button("Mostra") { model.reveal(output) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func outputName(for input: URL) -> String {
        (try? OutputFile.url(for: input).lastPathComponent) ?? "—"
    }

    private func loadDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matching.isEmpty else { return false }
        for provider in matching {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let candidate = item as? URL {
                    url = candidate
                } else if let string = item as? String {
                    url = URL(string: string)
                } else {
                    url = nil
                }
                if let url {
                    Task { @MainActor in
                        model.addFiles([url])
                    }
                }
            }
        }
        return true
    }
}
