//
//  PlanPersistence.swift
//  ManualTestPlan
//

import Foundation
import OSLog

/// Errors raised by ``PlanPersistence``.
nonisolated enum PlanPersistenceError: Error, Equatable {
    /// A plan ID or file name contained characters that could escape the storage directory.
    case invalidIdentifier(String)
}

/// Reads and writes plans and their evidence images on disk.
///
/// Layout, relative to `rootDirectory`:
/// ```
/// <planID>/plan.json
/// <planID>/evidence/<evidenceID>.<extension>
/// ```
/// Everything belonging to a plan lives inside its own directory, so removing the directory removes the
/// plan and all of its evidence together. This type performs no debouncing; callers decide when to save.
actor PlanPersistence {
    /// File name of the plan document inside each plan directory.
    nonisolated static let planFilename = "plan.json"
    /// Name of the evidence subdirectory inside each plan directory.
    nonisolated static let evidenceDirectoryName = "evidence"

    /// The directory that contains one subdirectory per plan.
    nonisolated let rootDirectory: URL

    private let logger = Logger(subsystem: "com.joshuasullivan.ManualTestPlan", category: "Persistence")

    /// The default storage location inside the app's sandbox container.
    nonisolated static var defaultRootDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "ManualTestPlan/plans", directoryHint: .isDirectory)
    }

    /// Creates a persistence layer.
    /// - Parameter rootDirectory: Where plan directories are stored. Tests pass a temporary directory.
    init(rootDirectory: URL = PlanPersistence.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    // MARK: - Plans

    /// Loads every readable plan, oldest first.
    ///
    /// A directory whose `plan.json` fails to decode is logged and skipped but never deleted, so a schema
    /// change or partial write can't silently destroy a user's results.
    func loadAll() -> [TestPlan] {
        let decoder = JSONDecoder()
        var plans: [TestPlan] = []
        for directory in planDirectories() {
            guard let data = try? Data(contentsOf: directory.appending(path: Self.planFilename)) else {
                continue
            }
            do {
                let plan = try decoder.decode(TestPlan.self, from: data)
                guard plan.id == directory.lastPathComponent else {
                    logger.error("Skipping \(directory.lastPathComponent, privacy: .public): plan.json contains ID \(plan.id, privacy: .public)")
                    continue
                }
                plans.append(plan)
            } catch {
                logger.error("Skipping \(directory.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return plans.sorted { $0.createdAt < $1.createdAt }
    }

    /// Atomically writes a plan's `plan.json`, creating its directory if needed.
    /// - Parameter plan: The plan to save.
    func save(_ plan: TestPlan) throws {
        let directory = try planDirectory(for: plan.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(plan)
        try data.write(to: directory.appending(path: Self.planFilename), options: .atomic)
    }

    /// Deletes a plan's entire directory: `plan.json` and every evidence image.
    ///
    /// Deleting a plan that isn't on disk is not an error. Any other failure is thrown so the caller never
    /// reports a plan as removed while its files remain.
    /// - Parameter planID: The plan to delete.
    func delete(planID: String) throws {
        let directory = try planDirectory(for: planID)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Evidence

    /// Writes an evidence file's bytes into the plan's evidence directory.
    /// - Parameters:
    ///   - data: The file's contents.
    ///   - filename: The stored file name, from ``EvidenceFile/storedFilename``.
    ///   - planID: The owning plan.
    func writeEvidence(_ data: Data, filename: String, planID: String) throws {
        let url = try evidenceURL(filename: filename, planID: planID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Reads an evidence file's bytes.
    /// - Parameters:
    ///   - filename: The stored file name.
    ///   - planID: The owning plan.
    func readEvidence(filename: String, planID: String) throws -> Data {
        try Data(contentsOf: evidenceURL(filename: filename, planID: planID))
    }

    /// Where an evidence file lives on disk.
    ///
    /// Agents run as the same user and can read this path, which lets them open files too large or too
    /// binary to be returned inline. The file is deleted when the plan is completed.
    /// - Parameters:
    ///   - filename: The stored file name.
    ///   - planID: The owning plan.
    nonisolated func evidenceFileURL(filename: String, planID: String) throws -> URL {
        try evidenceURL(filename: filename, planID: planID)
    }

    /// Deletes one evidence file. A missing file is not an error.
    /// - Parameters:
    ///   - filename: The stored file name.
    ///   - planID: The owning plan.
    func deleteEvidence(filename: String, planID: String) throws {
        let url = try evidenceURL(filename: filename, planID: planID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Maintenance

    /// Removes files that no live plan references.
    ///
    /// Removes (a) plan directories with no `plan.json` at all, such as leftovers from a crash during
    /// creation, and (b) evidence files in a known plan's directory that no step references. Directories
    /// whose `plan.json` exists but didn't decode are left alone.
    /// - Parameter knownPlans: The plans currently loaded in memory.
    /// - Returns: The paths removed, relative to the root, for logging and tests.
    @discardableResult
    func sweepOrphans(knownPlans: [TestPlan]) -> [String] {
        let fileManager = FileManager.default
        var removed: [String] = []

        for directory in planDirectories() {
            let planFile = directory.appending(path: Self.planFilename)
            if !fileManager.fileExists(atPath: planFile.path(percentEncoded: false)) {
                if (try? fileManager.removeItem(at: directory)) != nil {
                    removed.append(directory.lastPathComponent)
                }
            }
        }

        for plan in knownPlans {
            guard let directory = try? planDirectory(for: plan.id) else { continue }
            let evidenceDirectory = directory.appending(path: Self.evidenceDirectoryName, directoryHint: .isDirectory)
            guard let files = try? fileManager.contentsOfDirectory(atPath: evidenceDirectory.path(percentEncoded: false)) else {
                continue
            }
            let referenced = Set(plan.cases.flatMap(\.steps).flatMap(\.evidence).map(\.storedFilename))
            for file in files where !referenced.contains(file) {
                if (try? fileManager.removeItem(at: evidenceDirectory.appending(path: file))) != nil {
                    removed.append("\(plan.id)/\(Self.evidenceDirectoryName)/\(file)")
                }
            }
        }

        for path in removed {
            logger.info("Removed orphan \(path, privacy: .public)")
        }
        return removed
    }

    // MARK: - Paths

    /// The directory for a plan, validated so an agent-supplied ID can't traverse out of the root.
    private nonisolated func planDirectory(for planID: String) throws -> URL {
        guard planID.wholeMatch(of: /[a-z0-9_]+/) != nil else {
            throw PlanPersistenceError.invalidIdentifier(planID)
        }
        return rootDirectory.appending(path: planID, directoryHint: .isDirectory)
    }

    private nonisolated func evidenceURL(filename: String, planID: String) throws -> URL {
        guard filename.wholeMatch(of: /[a-z0-9_]+\.[a-z0-9]{1,16}/) != nil else {
            throw PlanPersistenceError.invalidIdentifier(filename)
        }
        return try planDirectory(for: planID)
            .appending(path: Self.evidenceDirectoryName, directoryHint: .isDirectory)
            .appending(path: filename)
    }

    private func planDirectories() -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let contents = (try? FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: keys)) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: Set(keys)).isDirectory) == true }
    }
}
