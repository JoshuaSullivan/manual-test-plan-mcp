//
//  MenuRowLabelStyle.swift
//  ManualTestPlan
//

import SwiftUI

/// Lays out a label with its icon in a fixed-width column so titles line up across rows,
/// whatever the width of each SF Symbol.
struct MenuRowLabelStyle: LabelStyle {
    @ScaledMetric private var iconWidth = 20.0

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
                .frame(width: iconWidth)
            configuration.title
        }
    }
}
