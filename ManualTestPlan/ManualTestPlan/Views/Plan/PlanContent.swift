//
//  PlanContent.swift
//  ManualTestPlan
//

import SwiftUI

/// The scrolling body of a plan window: a header followed by one collapsible section per case.
struct PlanContent: View {
    let plan: TestPlan

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                PlanHeader(plan: plan)
                ForEach(plan.cases) { testCase in
                    CaseSection(planID: plan.id, testCase: testCase)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem {
                Button("Copy Report", systemImage: "doc.on.doc") {
                    Clipboard.copy(PlanReport.markdown(for: plan))
                }
                .help("Copy the results as Markdown")
            }
        }
    }
}
