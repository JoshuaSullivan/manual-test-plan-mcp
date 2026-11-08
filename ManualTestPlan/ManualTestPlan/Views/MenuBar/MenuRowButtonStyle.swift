//
//  MenuRowButtonStyle.swift
//  ManualTestPlan
//

import SwiftUI

/// Gives each row in the menu bar popover breathing room and a hover highlight, like a native menu item.
///
/// `.plain` buttons add no padding, which packs the rows tightly together.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: Configuration
        @State private var isHovering = false
        @ScaledMetric private var verticalInset = 6.0
        @ScaledMetric private var horizontalInset = 8.0

        var body: some View {
            configuration.label
                .padding(.vertical, verticalInset)
                .padding(.horizontal, horizontalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(highlight, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
                .onHover { isHovering = $0 }
        }

        private var highlight: Color {
            if configuration.isPressed { return .primary.opacity(0.18) }
            return isHovering ? .primary.opacity(0.10) : .clear
        }
    }
}
