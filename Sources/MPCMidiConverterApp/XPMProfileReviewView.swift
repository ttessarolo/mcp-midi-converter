import SwiftUI

struct XPMProfileReviewView: View {
    @ObservedObject var draft: XPMImportDraft
    let onCancel: () -> Void
    let onInstall: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            identity
            sourceSummary
            warnings
            mappingTable
            reviewConfirmation
            actionBar
        }
        .padding(22)
        .frame(minWidth: 980, minHeight: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Create a Mapping Profile from XPM")
                .font(.title2.bold())
            Text("Sample names are suggestions, not proof. Review every primary mapping, fallback, and unavailable instrument before installing the profile.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Every row starts as Unavailable. Name-based suggestions are medium-confidence evidence; you must explicitly promote each accepted row to Primary or Fallback.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var identity: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Profile Name")
                TextField("Visible profile name", text: $draft.profileName)
            }
            GridRow {
                Text("Profile ID")
                TextField("Stable catalog identifier", text: $draft.profileID)
                    .fontDesign(.monospaced)
            }
            GridRow {
                Text("Target Drum Program")
                TextField("Public-safe MPC program name", text: $draft.targetProgramName)
            }
            GridRow {
                Text("Silent Pad")
                Picker("", selection: $draft.silentNote) {
                    Text("Choose an empty pad").tag(Optional<UInt8>.none)
                    ForEach(draft.emptyPads) { pad in
                        Text(draft.silentLabel(for: pad)).tag(Optional.some(pad.note))
                    }
                }
                .labelsHidden()
                .onChange(of: draft.silentNote) { _ in
                    draft.confirmedReview = false
                }
            }
        }
    }

    private var sourceSummary: some View {
        GroupBox("Read-only XPM analysis") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow { Text("Program"); Text(draft.analysis.programName) }
                GridRow { Text("Format"); Text(draft.formatLabel) }
                GridRow { Text("Populated pads"); Text("\(draft.populatedPads.count) of 128") }
                GridRow {
                    Text("XPM SHA-256")
                    Text(draft.xpmSHA256)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if !draft.warnings.isEmpty {
            DisclosureGroup("Review warnings (\(draft.warnings.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(draft.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 5)
            }
        }
    }

    private var mappingTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("GM Instrument").frame(width: 210, alignment: .leading)
                Text("Decision").frame(width: 120, alignment: .leading)
                Text("Destination MPC Pad").frame(maxWidth: .infinity, alignment: .leading)
                Text("Imported suggestion").frame(width: 220, alignment: .leading)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach($draft.rows) { $row in
                        HStack(spacing: 10) {
                            Text("\(row.gmNote) · \(row.gmInstrument)")
                                .frame(width: 210, alignment: .leading)

                            Picker("", selection: $row.disposition) {
                                ForEach(XPMMappingDisposition.allCases) { disposition in
                                    Text(disposition.title).tag(disposition)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                            .onChange(of: row.disposition) { disposition in
                                draft.confirmedReview = false
                                if disposition != .unavailable, row.targetNote == nil {
                                    row.targetNote = row.suggestedTarget ?? draft.populatedPads.first?.note
                                }
                            }

                            if row.disposition == .unavailable {
                                Text("Routes to the silent pad under silence/fallback policies")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Picker("", selection: $row.targetNote) {
                                    Text("Choose a populated pad").tag(Optional<UInt8>.none)
                                    ForEach(draft.populatedPads) { pad in
                                        Text(draft.targetLabel(for: pad)).tag(Optional.some(pad.note))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .onChange(of: row.targetNote) { _ in
                                    draft.confirmedReview = false
                                }
                            }

                            suggestion(for: row)
                                .frame(width: 220, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(minHeight: 250)
        }
    }

    @ViewBuilder
    private func suggestion(for row: XPMReviewRow) -> some View {
        if let target = row.suggestedTarget,
           let sample = row.suggestedSampleName,
           let confidence = row.suggestionConfidence {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(confidence.rawValue.capitalized) confidence · note \(target)")
                    .foregroundStyle(.blue)
                Text(sample)
                    .lineLimit(1)
                    .help(sample)
            }
            .font(.caption)
        } else {
            Text("No unambiguous suggestion")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var reviewConfirmation: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(
                "I explicitly classified the mappings I accept, reviewed every fallback, and confirmed that the selected silent pad is empty.",
                isOn: $draft.confirmedReview
            )
            Text("Preparing a GitHub submission opens an editable issue in your browser. Nothing is uploaded or submitted automatically, and sample names are omitted from the issue body.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = draft.actionError ?? draft.validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
            Spacer()
            Button("Install Locally", action: onInstall)
                .disabled(!draft.canInstall)
            Button("Install & Prepare GitHub Issue", action: onSubmit)
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canInstall)
        }
    }
}
