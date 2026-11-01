//
//  StepRow.swift
//  ManualTestPlan
//

import SwiftUI

/// One step: what to do, what to expect, the verdict buttons, a note field, and attached evidence.
///
/// The whole row accepts dropped files and pasted images, so users can drop a log anywhere on the step.
/// When the row itself has keyboard focus, P / F / B record a verdict and the arrow keys move between steps.
struct StepRow: View {
    let plan: TestPlan
    let step: TestStep
    let navigator: StepNavigator
    let focusedStep: FocusState<String?>.Binding

    @Environment(AppModel.self) private var model
    @FocusState private var isEditingNote: Bool
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

                StatusPicker(status: step.status, select: choose)

                TextField("Notes", text: noteBinding, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditingNote)

                EvidenceStrip(planID: plan.id, step: step) { urls in
                    attach { await attacher.attach(urls: urls) }
                }
            }
        }
        .padding(.vertical)
        .background(isTargeted ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .focusable()
        .focusEffectDisabled()
        .focused(focusedStep, equals: step.id)
        .onKeyPress(phases: .down) { press in
            handle(press)
        }
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

    // MARK: - Verdicts and keys

    /// Records a verdict from a button or key press, then moves the user where they'll want to be next:
    /// the note field after a failure or block (so they can say what happened), or the next unjudged step
    /// after a pass.
    private func choose(_ choice: StepStatus) {
        let newStatus = choice.afterSelecting(from: step.status)
        try? model.store.setStatus(newStatus, forStep: step.id, inPlan: plan.id)
        switch newStatus {
        case .failed, .blocked:
            isEditingNote = true
        case .passed:
            if let next = navigator.nextPending(after: step.id, in: plan) {
                focusedStep.wrappedValue = next
            }
        case .pending:
            break
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Typing in the note field must never be mistaken for a shortcut.
        guard !isEditingNote, press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .downArrow:
            return move(to: navigator.next(after: step.id))
        case .upArrow:
            return move(to: navigator.previous(before: step.id))
        default:
            guard let choice = StatusKey.status(for: press.characters) else { return .ignored }
            choose(choice)
            return .handled
        }
    }

    private func move(to stepID: String?) -> KeyPress.Result {
        guard let stepID else { return .ignored }
        focusedStep.wrappedValue = stepID
        return .handled
    }

    // MARK: - Attachments and bindings

    private var attacher: EvidenceAttacher {
        EvidenceAttacher(store: model.store, planID: plan.id, stepID: step.id)
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { step.note },
            set: { try? model.store.setNote($0, forStep: step.id, inPlan: plan.id) }
        )
    }

    private var failureAlertBinding: Binding<Bool> {
        Binding(get: { !attachFailures.isEmpty }, set: { if !$0 { attachFailures = [] } })
    }

    private func attach(_ work: @escaping () async -> [String]) {
        Task { attachFailures = await work() }
    }
}
