//
//  PlanContent.swift
//  ManualTestPlan
//

import SwiftUI

/// The scrolling body of a plan window: a header followed by one collapsible section per case.
///
/// Once the header scrolls away, a floating bar keeps overall progress in view and offers buttons that jump
/// to the previous or next step still awaiting a verdict.
struct PlanContent: View {
    let plan: TestPlan

    @FocusState private var focusedStep: String?
    /// The step the user last focused or jumped to. Unlike `focusedStep` it survives focus moving into a
    /// note field, so the jump buttons always work relative to where the user actually is.
    @State private var currentStep: String?
    @State private var collapsedCases: Set<String> = []
    @State private var isHeaderVisible = true

    var body: some View {
        let navigator = StepNavigator(plan: plan)
        // ScrollViewReader rather than ScrollPosition: steps sit inside each case's DisclosureGroup, and
        // ScrollPosition can only scroll to children of the outermost scroll target layout.
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: scrolling to a step needs its row to exist, and plans are small.
                VStack(alignment: .leading) {
                    PlanHeader(plan: plan)
                        .onScrollVisibilityChange(threshold: 0.05) { isHeaderVisible = $0 }
                    ForEach(plan.cases) { testCase in
                        CaseSection(
                            plan: plan,
                            testCase: testCase,
                            navigator: navigator,
                            focusedStep: $focusedStep,
                            isExpanded: expansion(of: testCase.id)
                        )
                    }
                }
                .padding()
            }
            .overlay(alignment: .top) {
                if !isHeaderVisible {
                    PlanFloatingBar(
                        progress: plan.progress,
                        goToPrevious: { jump(forward: false, navigator: navigator, proxy: proxy) },
                        goToNext: { jump(forward: true, navigator: navigator, proxy: proxy) }
                    )
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: isHeaderVisible)
        }
        .onChange(of: focusedStep) { _, step in
            if let step { currentStep = step }
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

    private func expansion(of caseID: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedCases.contains(caseID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedCases.remove(caseID)
                } else {
                    collapsedCases.insert(caseID)
                }
            }
        )
    }

    /// Moves to the nearest step without a verdict: opens its case if collapsed, focuses it, and scrolls it
    /// to the middle of the window so the floating bar doesn't cover it.
    private func jump(forward: Bool, navigator: StepNavigator, proxy: ScrollViewProxy) {
        guard let target = navigator.pendingStep(from: currentStep, forward: forward, in: plan) else { return }
        if let caseIndex = plan.location(ofStep: target)?.caseIndex {
            collapsedCases.remove(plan.cases[caseIndex].id)
        }
        currentStep = target
        focusedStep = target
        Task {
            // Let an expanding section lay out its rows before scrolling to one of them.
            await Task.yield()
            withAnimation { proxy.scrollTo(target, anchor: .center) }
        }
    }
}
