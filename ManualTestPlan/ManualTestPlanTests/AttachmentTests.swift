//
//  AttachmentTests.swift
//  ManualTestPlanTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ManualTestPlan

/// Builds real image files so the tests exercise ImageIO rather than a mock.
nonisolated enum TestImages {
    static func data(width: Int, height: Int, as type: UTType) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func size(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    static func type(of data: Data) -> UTType? {
        CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceGetType($0) as String? }
            .flatMap { UTType($0) }
    }
}

struct AttachmentPreparerTests {
    @Test func keepsSmallPNGAndJPEGBytesUntouched() async {
        for (type, name) in [(UTType.png, "shot.png"), (.jpeg, "photo.jpg")] {
            let original = TestImages.data(width: 200, height: 100, as: type)
            let result = await AttachmentPreparer.prepare(AttachmentPayload(name: name, data: original))
            #expect(result.data == original, "\(name)")
            #expect(result.name == name)
        }
    }

    @Test func convertsTIFFFromThePasteboardToNamedPNG() async throws {
        let tiff = TestImages.data(width: 120, height: 80, as: .tiff)
        let result = await AttachmentPreparer.prepare(AttachmentPayload(name: "", data: tiff))

        #expect(result.name == "Pasted Image.png")
        #expect(TestImages.type(of: result.data) == .png)
        let size = try #require(TestImages.size(of: result.data))
        #expect(size.width == 120 && size.height == 80)
    }

    @Test func keepsTheBaseNameWhenConvertingAFile() async {
        let heicLike = TestImages.data(width: 50, height: 50, as: .tiff)
        let result = await AttachmentPreparer.prepare(AttachmentPayload(name: "Screen Shot.tiff", data: heicLike))
        #expect(result.name == "Screen Shot.png")
    }

    @Test func downscalesOversizedImagesToTheCap() async throws {
        let big = TestImages.data(width: AttachmentPreparer.maxImagePixelSize * 2, height: 400, as: .png)
        let result = await AttachmentPreparer.prepare(AttachmentPayload(name: "wide.png", data: big))

        #expect(TestImages.type(of: result.data) == .png)
        let size = try #require(TestImages.size(of: result.data))
        #expect(size.width == AttachmentPreparer.maxImagePixelSize)
        #expect(size.height < 400)
        #expect(result.name == "wide.png")
        #expect(result.data.count < big.count)
    }

    @Test func leavesNonImagesAlone() async {
        let log = AttachmentPayload(name: "app.log", data: Data("hello".utf8))
        #expect(await AttachmentPreparer.prepare(log) == log)

        let binary = AttachmentPayload(name: "dump.bin", data: Data([0, 1, 2, 3, 255]))
        #expect(await AttachmentPreparer.prepare(binary) == binary)
    }

    @Test func leavesPDFsAlone() async {
        let pdf = Data("%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n".utf8)
        let payload = AttachmentPayload(name: "report.pdf", data: pdf)
        #expect(await AttachmentPreparer.prepare(payload) == payload)
    }

    @Test func namesAnonymousNonImageData() async {
        let result = await AttachmentPreparer.prepare(AttachmentPayload(name: "", data: Data("text".utf8)))
        #expect(result.name == "Attachment")
    }

    @Test func buildsThumbnailsOnlyForImages() async throws {
        let png = TestImages.data(width: 1000, height: 500, as: .png)
        let thumbnail = try #require(await AttachmentPreparer.thumbnail(from: png, maxPixelSize: 100))
        #expect(max(thumbnail.width, thumbnail.height) == 100)

        #expect(await AttachmentPreparer.thumbnail(from: Data("not an image".utf8), maxPixelSize: 100) == nil)
        #expect(await AttachmentPreparer.thumbnail(from: Data(), maxPixelSize: 100) == nil)
    }
}

struct AttachmentPayloadTests {
    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try contents.write(to: url)
        return url
    }

    @Test func loadsAFileWithItsNameAndBytes() throws {
        let url = try temporaryFile(named: "crash.log", contents: Data("boom".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let payload = AttachmentPayload.load(from: url)
        #expect(payload.name == "crash.log")
        #expect(payload.data == Data("boom".utf8))
        #expect(payload.problem == nil)
    }

    @Test func reportsMissingFilesAndFolders() throws {
        let missing = AttachmentPayload.load(from: URL.temporaryDirectory.appending(path: "nope-\(UUID().uuidString).log"))
        #expect(missing.problem != nil)
        #expect(missing.data.isEmpty)

        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(AttachmentPayload.load(from: folder).problem?.contains("folder") == true)
    }

    @Test func refusesOversizedFilesWithoutReadingThem() throws {
        let url = try temporaryFile(named: "huge.bin", contents: Data())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(EvidenceFile.maxByteCount + 1))
        try handle.close()

        let payload = AttachmentPayload.load(from: url)
        #expect(payload.problem?.contains("huge.bin") == true)
        #expect(payload.data.isEmpty)
    }
}

@MainActor
struct EvidenceAttacherTests {
    @Test func attachesPreparedFilesAndReportsFailuresIndividually() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let stepID = try #require(harness.store.plan(id: planID)?.cases[0].steps[0].id)
            let attacher = EvidenceAttacher(store: harness.store, planID: planID, stepID: stepID)

            let tiff = TestImages.data(width: 40, height: 40, as: .tiff)
            let failures = await attacher.attach([
                AttachmentPayload(name: "app.log", data: Data("log".utf8)),
                AttachmentPayload(name: "", data: tiff),
                AttachmentPayload(name: "big.zip", problem: "'big.zip' is too large."),
                AttachmentPayload(name: "dump.bin", data: Data(count: EvidenceFile.maxByteCount + 1))
            ])

            #expect(failures.count == 2)
            #expect(failures.contains("'big.zip' is too large."))
            let files = try #require(harness.store.plan(id: planID)?.step(withID: stepID)?.evidence)
            #expect(files.map(\.name) == ["app.log", "Pasted Image.png"])
            #expect(files[1].mimeType == "image/png")
        }
    }

    @Test func attachingToAFinishedPlanFailsCleanly() async throws {
        try await MCPHarness.run { harness in
            let created = await harness.createSamplePlan()
            let planID = try #require(created["plan_id"]?.stringValue)
            let stepID = try #require(harness.store.plan(id: planID)?.cases[0].steps[0].id)
            _ = try await harness.store.complete(planID: planID, force: true)

            let attacher = EvidenceAttacher(store: harness.store, planID: planID, stepID: stepID)
            let failures = await attacher.attach([AttachmentPayload(name: "a.log", data: Data("x".utf8))])
            #expect(failures.count == 1)
            #expect(!FileManager.default.fileExists(atPath: harness.root.appending(path: planID).path(percentEncoded: false)))
        }
    }
}

struct StatusSelectionTests {
    @Test func selectingAStatusSetsItAndSelectingAgainClearsIt() {
        #expect(StepStatus.passed.afterSelecting(from: .pending) == .passed)
        #expect(StepStatus.passed.afterSelecting(from: .failed) == .passed)
        #expect(StepStatus.passed.afterSelecting(from: .passed) == .pending)
        #expect(StepStatus.blocked.afterSelecting(from: .blocked) == .pending)
    }
}

@MainActor
struct AppModelTests {
    private func makeModel(defaults: UserDefaults) -> AppModel {
        AppModel(store: PlanStore(persistence: PlanPersistence(rootDirectory: URL.temporaryDirectory.appending(path: UUID().uuidString))), defaults: defaults)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "ManualTestPlanTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test(arguments: [(1023, false), (1024, true), (47821, true), (65535, true), (65536, false), (0, false), (-5, false)])
    func validatesPorts(port: Int, expected: Bool) {
        #expect(AppModel.isValid(port: port) == expected)
    }

    @Test func usesTheDefaultPortAndBuildsTheSetupCommand() {
        let model = makeModel(defaults: isolatedDefaults())
        #expect(model.port == AppModel.defaultPort)
        #expect(model.setupCommand == "claude mcp add --transport http manualtestplan http://127.0.0.1:47821/mcp")
    }

    @Test func rememembersAChosenPortAcrossLaunches() {
        let defaults = isolatedDefaults()
        let first = makeModel(defaults: defaults)
        first.changePort(to: 50_123)
        defer { first.server.stop() }
        #expect(first.port == 50_123)

        let second = makeModel(defaults: defaults)
        #expect(second.port == 50_123)
    }

    @Test func ignoresInvalidPorts() {
        let defaults = isolatedDefaults()
        let model = makeModel(defaults: defaults)
        model.changePort(to: 80)
        model.changePort(to: 70_000)
        #expect(model.port == AppModel.defaultPort)
        #expect(defaults.object(forKey: "serverPort") == nil)
    }

    @Test func ignoresACorruptSavedPort() {
        let defaults = isolatedDefaults()
        defaults.set(12, forKey: "serverPort")
        #expect(makeModel(defaults: defaults).port == AppModel.defaultPort)
    }

    @Test func countsOnlyPlansWithPendingSteps() async throws {
        let model = makeModel(defaults: isolatedDefaults())
        let waiting = model.store.createPlan(title: "Waiting", cases: [TestCase(title: "C", steps: [TestStep(instruction: "x")])])
        let done = model.store.createPlan(title: "Done", cases: [TestCase(title: "C", steps: [TestStep(instruction: "x")])])
        try model.store.setStatus(.passed, forStep: done.cases[0].steps[0].id, inPlan: done.id)

        #expect(model.plansNeedingAttention.map(\.id) == [waiting.id])
    }
}
