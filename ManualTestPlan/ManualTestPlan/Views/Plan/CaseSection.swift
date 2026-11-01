//
//  CaseSection.swift
//  ManualTestPlan
//

import SwiftUI

/// A collapsible group of steps. The header shows the case's rolled-up status so a collapsed section still
/// tells the user where things stand.
struct CaseSection: View {
    let plan: TestPlan
    let testCase: TestCase
    let navigator: StepNavigator
    let focusedStep: FocusState<String?>.Binding

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading) {
                if !testCase.preconditions.isEmpty {
                    Label(testCase.preconditions, systemImage: "list.bullet.clipboard")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(testCase.steps) { step in
                    StepRow(plan: plan, step: step, navigator: navigator, focusedStep: focusedStep)
                }
            }
            .padding(.top)
        } label: {
            CaseHeader(testCase: testCase)
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

/// The always-visible line of a case: status icon, title, and how many steps are done.
private struct CaseHeader: View {
    let testCase: TestCase

    var body: some View {
        let resolved = testCase.steps.count { $0.status != .pending }
        HStack {
            Image(systemName: testCase.status.symbolName)
                .foregroundStyle(testCase.status.tint)
            Text(testCase.title)
                .font(.headline)
            Spacer()
            Text("\(resolved) of \(testCase.steps.count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
