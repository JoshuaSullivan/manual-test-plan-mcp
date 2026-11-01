//
//  EvidenceThumbnail.swift
//  ManualTestPlan
//

import CoreGraphics
import SwiftUI

/// A small preview of an image attachment, decoded off the main thread.
struct EvidenceThumbnail: View {
    let planID: String
    let file: EvidenceFile

    @Environment(AppModel.self) private var model
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 72)
        .clipShape(.rect(cornerRadius: 6))
        .task(id: file.id) {
            guard let data = try? await model.store.evidenceData(for: file, inPlan: planID) else { return }
            image = await AttachmentPreparer.thumbnail(from: data, maxPixelSize: 240)
        }
    }
}
