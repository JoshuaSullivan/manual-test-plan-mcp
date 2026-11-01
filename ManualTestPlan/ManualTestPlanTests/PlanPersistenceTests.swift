//
//  PlanPersistenceTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

struct PlanPersistenceTests {
    /// A unique empty directory removed when the closure finishes.
    private func withTemporaryRoot(_ body: (URL) async throws -> Void) async throws {
        let root = URL.temporaryDirectory.appending(path: "ManualTestPlanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func makePlan() -> TestPlan {
        TestPlan(title: "Persist me", cases: [TestCase(title: "Case", steps: [TestStep(instruction: "Do it")])])
    }

    @Test func saveThenLoadRoundTrips() async throws {
        try await withTemporaryRoot { root in
            let persistence = PlanPersistence(rootDirectory: root)
            var plan = makePlan()
            plan.cases[0].steps[0].status = .failed
            plan.cases[0].steps[0].note = "Broke"
            try await persistence.save(plan)

            let loaded = await persistence.loadAll()
            #expect(loaded == [plan])
        }
    }

    @Test func loadAllIsOrderedByCreationDate() async throws {
        try await withTemporaryRoot { root in
            let persistence = PlanPersistence(rootDirectory: root)
            var older = makePlan()
            older.createdAt = Date(timeIntervalSince1970: 1_000)
            var newer = makePlan()
            newer.createdAt = Date(timeIntervalSince1970: 2_000)
            try await persistence.save(newer)
            try await persistence.save(older)

            let loaded = await persistence.loadAll()
            #expect(loaded.map(\.id) == [older.id, newer.id])
        }
    }

    @Test func deleteRemovesPlanAndAllEvidence() async throws {
        try await withTemporaryRoot { root in
            let persistence = PlanPersistence(rootDirectory: root)
            var plan = makePlan()
            let evidence = EvidenceFile(name: "shot.png", byteCount: 3)
            plan.cases[0].steps[0].evidence = [evidence]
            try await persistence.save(plan)
            try await persistence.writeEvidence(Data([1, 2, 3]), filename: evidence.storedFilename, planID: plan.id)
            let planDirectory = root.appending(path: plan.id)
            #expect(exists(planDirectory.appending(path: "evidence/\(evidence.storedFilename)")))

            try await persistence.delete(planID: plan.id)

            #expect(!exists(planDirectory))
            #expect(await persistence.loadAll().isEmpty)
        }
    }

    @Test func deletingMissingPlanIsNotAnError() async throws {
        try await withTemporaryRoot { root in
            let persistence = PlanPersistence(rootDirectory: root)
            try await persistence.delete(planID: "tp_missing")
        }
    }

    @Test func evidenceRoundTripAndDelete() async throws {
        try await withTemporaryRoot { root in
            let persistence = PlanPersistence(rootDirectory: root)
            let plan = makePlan()
            let evidence = EvidenceFile(name: "shot.png", byteCount: 3)
            let bytes = Data([9, 8, 7])
            try await persistence.writeEvidence(bytes, filename: evidence.storedFilename, planID: plan.id)

            #expect(try await persistence.readEvidence(filename: evidence.storedFilename, planID: plan.id) == bytes)

            try await persistence.deleteEvidence(filename: evidence.storedFilename, planID: plan.id)
            #expect(!exists(root.appending(path: "\(plan.id)/evidence/\(evidence.storedFilename)")))
            // Deleting again is harmless.
            try await persistence.deleteEvidence(filename: evidence.storedFilename, planID: plan.id)
        }
    }

    @Test func rejectsIdentifiersThatCouldEscapeTheRoot() async throws {
        try await withTemporaryRoot { root in
            let persistence = PlanPersistence(rootDirectory: root)
            await #expect(throws: PlanPersistenceError.invalidIdentifier("../outside")) {
                try await persistence.delete(planID: "../outside")
            }
            await #expect(throws: PlanPersistenceError.invalidIdentifier("../x.png")) {
                try await persistence.writeEvidence(Data(), filename: "../x.png", planID: "tp_abc")
            }
            var plan = makePlan()
            plan.id = "a/b"
            await #expect(throws: PlanPersistenceError.invalidIdentifier("a/b")) {
                try await persistence.save(plan)
            }
        }
    }

    @Test func sweepRemovesOnlyOrphans() async throws {
        try await withTemporaryRoot { root in
            let persistence = PlanPersistence(rootDirectory: root)
            var plan = makePlan()
            let kept = EvidenceFile(name: "shot.png", byteCount: 3)
            plan.cases[0].steps[0].evidence = [kept]
            try await persistence.save(plan)
            try await persistence.writeEvidence(Data([1]), filename: kept.storedFilename, planID: plan.id)
            let orphanImage = EvidenceFile(name: "shot.png", byteCount: 3)
            try await persistence.writeEvidence(Data([2]), filename: orphanImage.storedFilename, planID: plan.id)

            // A directory with no plan.json is a crash leftover.
            let orphanDirectory = root.appending(path: "tp_orphan", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)

            // A directory whose plan.json is present but unreadable must survive.
            let corruptDirectory = root.appending(path: "tp_corrupt", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: corruptDirectory.appending(path: "plan.json"))

            let known = await persistence.loadAll()
            #expect(known == [plan])
            let removed = await persistence.sweepOrphans(knownPlans: known)

            #expect(Set(removed) == ["tp_orphan", "\(plan.id)/evidence/\(orphanImage.storedFilename)"])
            #expect(exists(root.appending(path: "\(plan.id)/evidence/\(kept.storedFilename)")))
            #expect(!exists(root.appending(path: "\(plan.id)/evidence/\(orphanImage.storedFilename)")))
            #expect(!exists(orphanDirectory))
            #expect(exists(corruptDirectory.appending(path: "plan.json")))
        }
    }

    @Test func corruptPlanIsSkippedNotDeleted() async throws {
        try await withTemporaryRoot { root in
            let persistence = PlanPersistence(rootDirectory: root)
            let directory = root.appending(path: "tp_bad", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{".utf8).write(to: directory.appending(path: "plan.json"))
            try await persistence.save(makePlan())

            #expect(await persistence.loadAll().count == 1)
            #expect(exists(directory.appending(path: "plan.json")))
        }
    }
}
