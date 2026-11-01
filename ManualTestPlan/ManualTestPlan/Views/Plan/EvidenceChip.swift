//
//  EvidenceChip.swift
//  ManualTestPlan
//

import AppKit
import SwiftUI

/// One attachment: a thumbnail for images or a file icon otherwise. Click to open, right-click for more.
struct EvidenceChip: View {
    let planID: String
    let stepID: String
    let file: EvidenceFile

    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: open) {
            EvidenceChipLabel(planID: planID, file: file)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app", action: open)
            Button("Show in Finder", systemImage: "folder", action: reveal)
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive, action: remove)
        }
        .accessibilityLabel(Text("Attachment \(file.name)"))
        .help(file.name)
    }

    private var url: URL? {
        model.store.evidenceURL(for: file, inPlan: planID)
    }

    private func open() {
        if let url { NSWorkspace.shared.open(url) }
    }

    private func reveal() {
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func remove() {
        Task { try? await model.store.removeEvidence(file.id, fromStep: stepID, inPlan: planID) }
    }
}

/// The picture, name, and size shown for an attachment.
private struct EvidenceChipLabel: View {
    let planID: String
    let file: EvidenceFile

    var body: some View {
        VStack {
            if file.isImage {
                EvidenceThumbnail(planID: planID, file: file)
            } else {
                Image(systemName: "doc.text")
                    .imageScale(.large)
                    .frame(width: 96, height: 72)
            }
            Text(file.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Int64(file.byteCount), format: .byteCount(style: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 112)
        .padding(.vertical)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }
}
