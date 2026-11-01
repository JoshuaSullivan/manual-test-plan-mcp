//
//  EvidenceStrip.swift
//  ManualTestPlan
//

import SwiftUI
import UniformTypeIdentifiers

/// The attachments on a step, plus the controls for adding more.
///
/// Dropping and pasting are handled by ``StepRow`` so the whole row is a target; this view adds the
/// explicit "Attach…" button for people who prefer a file picker.
struct EvidenceStrip: View {
    let planID: String
    let step: TestStep
    /// Called with the files chosen in the picker.
    let attachURLs: ([URL]) -> Void

    @State private var isPickingFiles = false

    var body: some View {
        VStack(alignment: .leading) {
            if !step.evidence.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(step.evidence) { file in
                            EvidenceChip(planID: planID, stepID: step.id, file: file)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Button("Attach Files…", systemImage: "paperclip") {
                isPickingFiles = true
            }
            .controlSize(.small)
            .help("Attach screenshots, logs, or any other file. You can also drop files here or paste an image.")
        }
        .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                attachURLs(urls)
            }
        }
    }
}
