import AppKit
import MPCMidiConverterCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: ConverterViewModel
    @State private var dropIsTargeted = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    dropZone
                    options
                    actionBar
                    results
                        .id("conversion-results")
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .onChange(of: model.outcomes.count) { count in
                guard count > 0 else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("conversion-results", anchor: .bottom)
                }
            }
        }
        .sheet(item: $model.xpmDraft) { draft in
            XPMProfileReviewView(
                draft: draft,
                onCancel: model.dismissXPMDraft,
                onInstall: { model.installGeneratedProfile(draft) },
                onSubmit: { model.installAndPrepareProfileIssue(draft) }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("MPC MIDI Converter")
                    .font(.title3.bold())
                Text("General MIDI → Akai MPC drum-kit mapping")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var dropZone: some View {
        VStack(spacing: 7) {
            if model.files.isEmpty {
                Image(systemName: "music.note.list")
                    .font(.system(size: 28))
                    .foregroundStyle(dropIsTargeted ? Color.accentColor : .secondary)
                Text("Drop one or more .mid/.midi files here")
                    .font(.headline)
                Text("You can also drop files on the app icon in Finder or the Dock.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Choose Files…") {
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
                                .help("Remove")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        }
                    }
                }
                .frame(maxHeight: 110)

                HStack {
                    Button("Add…") { model.chooseFiles() }
                    Button("Remove All") { model.clearFiles() }
                    Spacer()
                    Text("\(model.files.count) file(s)")
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
        .frame(maxWidth: .infinity, minHeight: 105)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    dropIsTargeted
                        ? Color.accentColor.opacity(0.10)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.72)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    dropIsTargeted ? Color.accentColor : Color.primary.opacity(0.16),
                    lineWidth: dropIsTargeted ? 1.5 : 1
                )
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropIsTargeted) { providers in
            loadDroppedFiles(providers)
        }
    }

    private var options: some View {
        GroupBox("Conversion Options") {
            VStack(alignment: .leading, spacing: 10) {
                settingRow("Destination Profile") {
                    HStack(spacing: 8) {
                        Picker("", selection: $model.selectedProfile) {
                            ForEach(model.profiles) { profile in
                                Text(profile.name).tag(profile)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Button("Import…") { model.importProfile() }
                            .help("Import a JSON mapping profile for another kit")
                        Button {
                            model.chooseXPMProgram()
                        } label: {
                            if model.isAnalyzingXPM {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Create from XPM…")
                            }
                        }
                        .disabled(model.isAnalyzingXPM)
                        .help("Analyze an MPC Drum Program and review a new mapping profile")
                    }
                }

                settingRow("Unavailable Instruments") {
                    Picker("", selection: $model.unavailablePolicy) {
                        ForEach(UnavailableNotePolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300)
                }

                settingRow("Channels to Convert") {
                    Picker("", selection: $model.channelSelection) {
                        ForEach(MIDIChannelSelection.allCases) { channels in
                            Text(channels.title).tag(channels)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300)
                }

                Text(model.unavailablePolicy.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 174)

                HStack(spacing: 24) {
                    Toggle("Remap Polyphonic Key Pressure", isOn: $model.remapPolyphonicKeyPressure)
                    Toggle("Overwrite Existing Outputs", isOn: $model.overwriteExisting)
                }
                .padding(.leading, 174)

                Divider()

                DisclosureGroup("Profile Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.selectedProfile.description)
                        Text("\(model.selectedProfile.direct.count) primary mappings, \(model.selectedProfile.fallback.count) declared fallbacks, GM notes \(model.selectedProfile.gmRange.lowerBound)–\(model.selectedProfile.gmRange.upperBound).")
                        Text("All unrelated MIDI data remains byte-for-byte identical.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .padding(.top, 2)
        }
    }

    private var actionBar: some View {
        HStack {
            Text("Output is written next to the original with an -mpc suffix.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isConverting {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Convert") {
                model.convert()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(model.files.isEmpty || model.isConverting)
        }
        .padding(.horizontal, 1)
    }

    @ViewBuilder
    private var results: some View {
        if !model.outcomes.isEmpty {
            GroupBox("Results") {
                VStack(spacing: 8) {
                    ForEach(model.outcomes) { outcome in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(outcome.succeeded ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(outcome.input.lastPathComponent)
                                    .fontWeight(.medium)
                                if let report = outcome.report, let output = outcome.output {
                                    Text("Created \(output.lastPathComponent) · \(report.changedEvents) events changed, \(report.fallbackEvents) fallbacks, \(report.silencedEvents) silenced")
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
                                Button("Show in Finder") { model.reveal(output) }
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

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
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
