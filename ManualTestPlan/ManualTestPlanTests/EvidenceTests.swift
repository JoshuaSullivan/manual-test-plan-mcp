//
//  EvidenceTests.swift
//  ManualTestPlanTests
//

import Foundation
import Testing
@testable import ManualTestPlan

struct EvidenceFileTests {
    @Test func derivesExtensionAndMimeTypeFromTheName() {
        let png = EvidenceFile(name: "Screenshot 2026-11-01.PNG", byteCount: 10)
        #expect(png.fileExtension == "png")
        #expect(png.mimeType == "image/png")
        #expect(png.isImage)
        #expect(png.storedFilename == "\(png.id).png")
        #expect(png.name == "Screenshot 2026-11-01.PNG")

        let log = EvidenceFile(name: "crash.log", byteCount: 10)
        #expect(log.fileExtension == "log")
        #expect(!log.isImage)

        let json = EvidenceFile(name: "state.json", byteCount: 10)
        #expect(json.mimeType == "application/json")
    }

    @Test func fallsBackForMissingOrUnknownExtensions() {
        let none = EvidenceFile(name: "README", byteCount: 1)
        #expect(none.fileExtension == "bin")
        #expect(none.mimeType == "application/octet-stream")

        let unknown = EvidenceFile(name: "trace.zzqq9", byteCount: 1)
        #expect(unknown.fileExtension == "zzqq9")
        #expect(unknown.mimeType == "application/octet-stream")

        #expect(EvidenceFile(name: "   ", byteCount: 1).name == "Attachment")
    }

    @Test func sanitizesHostileNames() {
        let tricky = EvidenceFile(name: "../../etc/pass wd.t/x t", byteCount: 1)
        #expect(tricky.storedFilename.wholeMatch(of: /[a-z0-9_]+\.[a-z0-9]{1,16}/) != nil)

        // Non-ASCII characters are dropped from the extension; the stored name stays safe and the display name is untouched.
        let unicode = EvidenceFile(name: "report.ünï©ödé", byteCount: 1)
        #expect(unicode.storedFilename.wholeMatch(of: /[a-z0-9_]+\.[a-z0-9]{1,16}/) != nil)
        #expect(unicode.name == "report.ünï©ödé")

        let onlySymbols = EvidenceFile(name: "report.©©©", byteCount: 1)
        #expect(onlySymbols.fileExtension == "bin")

        #expect(EvidenceFile(name: "notes.txt~", byteCount: 1).fileExtension == "txt")

        let long = EvidenceFile(name: "x." + String(repeating: "a", count: 100), byteCount: 1)
        #expect(long.fileExtension.count == 16)
    }
}

struct EvidenceContentTests {
    private func file(_ name: String) -> EvidenceFile { EvidenceFile(name: name, byteCount: 0) }
    private func text(_ blocks: [MCPContent]) -> String {
        blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n")
    }

    @Test func imagesComeBackAsImageContent() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let blocks = EvidenceContent.blocks(for: file("shot.png"), data: bytes, localPath: "/x/shot.png")
        #expect(blocks == [.image(bytes, mimeType: "image/png")])
    }

    @Test func shortTextIsReturnedInlineRegardlessOfExtension() {
        let log = "2026-11-01 ERROR  Something broke\nstack trace…"
        for name in ["app.log", "notes", "data.csv", "weird.zzqq9"] {
            let blocks = EvidenceContent.blocks(for: file(name), data: Data(log.utf8), localPath: nil)
            #expect(text(blocks).contains(log), "\(name)")
            #expect(text(blocks).contains("Attachment '\(name)'"), "\(name)")
        }
    }

    @Test func emptyFilesCountAsText() {
        let blocks = EvidenceContent.blocks(for: file("empty.txt"), data: Data(), localPath: nil)
        #expect(text(blocks).contains("Attachment 'empty.txt'"))
    }

    @Test func longTextKeepsTheBeginningAndTheEnd() {
        let limit = EvidenceContent.maxInlineTextBytes
        let body = "START-MARKER\n" + String(repeating: "middle line\n", count: limit / 4) + "END-MARKER\n"
        #expect(body.utf8.count > limit * 2)

        let blocks = EvidenceContent.blocks(for: file("big.log"), data: Data(body.utf8), localPath: "/x/big.log")
        let result = text(blocks)

        #expect(result.contains("START-MARKER"))
        #expect(result.contains("END-MARKER"))
        #expect(result.contains("omitted"))
        #expect(result.contains("/x/big.log"))
        #expect(result.utf8.count < limit + 1024)
    }

    @Test func binaryDataIsDescribedNotInlined() {
        let bytes = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0x00, 0x42])
        let blocks = EvidenceContent.blocks(for: file("capture.bin"), data: bytes, localPath: "/x/capture.bin")

        #expect(blocks.count == 1)
        let result = text(blocks)
        #expect(result.contains("binary"))
        #expect(result.contains("capture.bin"))
        #expect(result.contains("/x/capture.bin"))
    }

    @Test func invalidUTF8WithoutNULsIsBinary() {
        #expect(!EvidenceContent.looksLikeText(Data([0xC3, 0x28, 0xA0, 0xA1, 0x41])))
    }

    @Test func aMultibyteCharacterCutByTheSniffWindowStillCountsAsText() {
        // 8 KB window boundary falls in the middle of "é" (2 bytes).
        let data = Data(String(repeating: "a", count: 8 * 1024 - 1).utf8) + Data("é and more".utf8)
        #expect(EvidenceContent.looksLikeText(data))
    }
}

@MainActor
struct EvidenceAttachmentTests {
    private func makePlan(_ harness: MCPHarness) async throws -> (planID: String, stepID: String) {
        let created = await harness.createSamplePlan()
        let planID = try #require(created["plan_id"]?.stringValue)
        let stepID = try #require(harness.store.plan(id: planID)?.cases[0].steps[0].id)
        return (planID, stepID)
    }

    @Test func anyFileTypeCanBeAttachedAndIsStoredWithItsExtension() async throws {
        try await MCPHarness.run { harness in
            let (planID, stepID) = try await makePlan(harness)
            let log = Data("ERROR boom".utf8)

            let file = try await harness.store.addEvidence(log, named: "crash report.LOG", toStep: stepID, inPlan: planID)

            #expect(file.name == "crash report.LOG")
            #expect(file.byteCount == log.count)
            let onDisk = harness.root.appending(path: "\(planID)/evidence/\(file.id).log")
            #expect(try Data(contentsOf: onDisk) == log)
            #expect(harness.store.plan(id: planID)?.step(withID: stepID)?.evidence == [file])
        }
    }

    @Test func oversizedFilesAreRefusedWithoutLeavingAnythingBehind() async throws {
        try await MCPHarness.run { harness in
            let (planID, stepID) = try await makePlan(harness)
            let huge = Data(count: EvidenceFile.maxByteCount + 1)

            await #expect(throws: PlanStoreError.evidenceTooLarge(name: "dump.bin", limit: EvidenceFile.maxByteCount)) {
                try await harness.store.addEvidence(huge, named: "dump.bin", toStep: stepID, inPlan: planID)
            }
            #expect(harness.store.plan(id: planID)?.step(withID: stepID)?.evidence.isEmpty == true)
            #expect(!FileManager.default.fileExists(atPath: harness.root.appending(path: "\(planID)/evidence").path(percentEncoded: false)))
        }
    }

    @Test func toolReturnsLogsInlineAndImagesAsImages() async throws {
        try await MCPHarness.run { harness in
            let (planID, stepID) = try await makePlan(harness)
            let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2])
            try await harness.store.addEvidence(Data("line one\nFATAL: disk full".utf8), named: "app.log", toStep: stepID, inPlan: planID)
            try await harness.store.addEvidence(png, named: "screen.png", toStep: stepID, inPlan: planID)

            let reply = await harness.call("get_step_evidence", ["plan_id": .string(planID), "step_id": .string(stepID)])

            #expect(!reply.isError)
            #expect(reply.images == [png])
            let allText = reply.content.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
            #expect(allText.contains("FATAL: disk full"))

            let listed = try #require(reply.json["evidence"]?.arrayValue)
            #expect(listed.map { $0["name"]?.stringValue } == ["app.log", "screen.png"])
            #expect(listed[1]["mime_type"]?.stringValue == "image/png")
            #expect(listed[0]["mime_type"]?.stringValue?.isEmpty == false)
            #expect(listed.map { $0["bytes"] } == [.int(25), .int(png.count)])
            #expect(listed.allSatisfy { $0["local_path"]?.stringValue?.hasPrefix(harness.root.path(percentEncoded: false)) == true })
        }
    }

    @Test func toolDescribesBinaryFilesAndGivesTheirPath() async throws {
        try await MCPHarness.run { harness in
            let (planID, stepID) = try await makePlan(harness)
            let file = try await harness.store.addEvidence(Data([0, 1, 2, 0xFF]), named: "recording.mov", toStep: stepID, inPlan: planID)

            let reply = await harness.call("get_step_evidence", ["plan_id": .string(planID), "step_id": .string(stepID)])

            let allText = reply.content.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
            #expect(allText.contains("recording.mov"))
            #expect(allText.contains("binary"))
            #expect(allText.contains("\(file.id).mov"))
            #expect(reply.images.isEmpty)
        }
    }

    @Test func planListingsMentionAttachmentsButNotPaths() async throws {
        try await MCPHarness.run { harness in
            let (planID, stepID) = try await makePlan(harness)
            try await harness.store.addEvidence(Data("x".utf8), named: "a.log", toStep: stepID, inPlan: planID)
            try harness.store.setStatus(.failed, forStep: stepID, inPlan: planID)

            let plan = await harness.call("get_test_plan", ["plan_id": .string(planID)]).json
            let step = try #require(plan["cases"]?.arrayValue?[0]["steps"]?.arrayValue?.first)
            #expect(step["evidence_count"] == 1)
            #expect(step["evidence"]?.arrayValue?.first?["name"]?.stringValue == "a.log")
            #expect(step["evidence"]?.arrayValue?.first?["local_path"] == nil)
        }
    }

    @Test func completingDeletesEveryKindOfAttachment() async throws {
        try await MCPHarness.run { harness in
            let (planID, stepID) = try await makePlan(harness)
            try await harness.store.addEvidence(Data("x".utf8), named: "a.log", toStep: stepID, inPlan: planID)
            try await harness.store.addEvidence(Data([0, 1]), named: "b.bin", toStep: stepID, inPlan: planID)
            try await harness.store.addEvidence(Data("{}".utf8), named: "c.json", toStep: stepID, inPlan: planID)

            let reply = await harness.call("complete_test_plan", ["plan_id": .string(planID), "force": true])

            #expect(!reply.isError)
            #expect(reply.text.contains("Evidence: a.log, b.bin, c.json"))
            #expect(!FileManager.default.fileExists(atPath: harness.root.appending(path: planID).path(percentEncoded: false)))
        }
    }
}
