//
//  StepRow.swift
//  ManualTestPlan
//

import SwiftUI

/// One step: what to do, what to expect, the verdict buttons, a note field, and attached evidence.
///
/// The whole row accepts dropped files and pasted images, so users can drop a log anywhere on the step.
struct StepRow: View {
    let planID: String
    let step: TestStep

    @Environment(AppModel.self) private var model
    @State private var attachFailures: [String] = []
    @State private var isTargeted = false

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: step.status.symbolName)
                .foregroundStyle(step.status.tint)
                .imageScale(.large)
                .accessibilityLabel(Text(step.status.title))

            VStack(alignment: .leading) {
                Text(step.instruction)

                if !step.expected.isEmpty {
                    Text("Expected: \(step.expected)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                StatusPicker(status: step.status) { newStatus in
                    try? model.store.setStatus(newStatus, forStep: step.id, inPlan: planID)
                }

                TextField("Notes", text: noteBinding, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)

                EvidenceStrip(planID: planID, step: step) { urls in
                    attach { await attacher.attach(urls: urls) }
                }
            }
        }
        .padding(.vertical)
        .background(isTargeted ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .dropDestination(for: AttachmentPayload.self) { payloads, _ in
            attach { await attacher.attach(payloads) }
            return !payloads.isEmpty
        } isTargeted: { isTargeted = $0 }
        .pasteDestination(for: AttachmentPayload.self) { payloads in
            attach { await attacher.attach(payloads) }
        }
        .alert("Couldn't Attach", isPresented: failureAlertBinding) {
            Button("OK") { attachFailures = [] }
        } message: {
            Text(attachFailures.joined(separator: "\n"))
        }
    }

    private var attacher: EvidenceAttacher {
        EvidenceAttacher(store: model.store, planID: planID, stepID: step.id)
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { step.note },
            set: { try? model.store.setNote($0, forStep: step.id, inPlan: planID) }
        )
    }

    private var failureAlertBinding: Binding<Bool> {
        Binding(get: { !attachFailures.isEmpty }, set: { if !$0 { attachFailures = [] } })
    }

    private func attach(_ work: @escaping () async -> [String]) {
        Task { attachFailures = await work() }
    }
}
