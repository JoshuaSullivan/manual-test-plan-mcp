//
//  StatusPicker.swift
//  ManualTestPlan
//

import SwiftUI

/// Three buttons for recording a verdict. The caller decides what pressing the active one again means.
struct StatusPicker: View {
    let status: StepStatus
    /// Called with the button the user pressed.
    let select: (StepStatus) -> Void

    private static let choices: [StepStatus] = [.passed, .failed, .blocked]

    var body: some View {
        HStack {
            ForEach(Self.choices, id: \.self) { choice in
                StatusButton(choice: choice, isSelected: status == choice) {
                    select(choice)
                }
            }
        }
        .controlSize(.small)
    }
}

private struct StatusButton: View {
    let choice: StepStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) {
                Label(choice.title, systemImage: choice.symbolName)
            }
            .buttonStyle(.borderedProminent)
            .tint(choice.tint)
        } else {
            Button(action: action) {
                Label(choice.title, systemImage: choice.symbolName)
            }
            .buttonStyle(.bordered)
        }
    }
}
