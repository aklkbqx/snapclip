import Foundation
import Testing
@testable import SnapClipCore

@Suite("DestinationStore")
struct DestinationStoreTests {
    @Test("Sorts supported media oldest-first and ignores unsupported extensions")
    func sortsChronologicallyAndFilters() throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = DestinationStore()
        let first = dir.appendingPathComponent("b-first.png")
        let second = dir.appendingPathComponent("a-second.mov")
        let ignored = dir.appendingPathComponent("notes.txt")

        try Data("one".utf8).write(to: first)
        Thread.sleep(forTimeInterval: 0.03)
        try Data("two".utf8).write(to: second)
        try Data("skip".utf8).write(to: ignored)

        let all = store.sortedMediaURLs(in: dir, includeVideos: true)
        #expect(all.map(\.lastPathComponent) == ["b-first.png", "a-second.mov"])

        let imagesOnly = store.sortedMediaURLs(in: dir, includeVideos: false)
        #expect(imagesOnly.map(\.lastPathComponent) == ["b-first.png"])
    }

    @Test("Resolves filename collisions with numbered suffixes")
    func resolvesCollisions() throws {
        let dir = try TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = DestinationStore()
        let name = "Screenshot.png"
        let first = store.uniqueDestinationURL(for: name, in: dir)
        #expect(first.lastPathComponent == "Screenshot.png")
        try Data("1".utf8).write(to: first)

        let second = store.uniqueDestinationURL(for: name, in: dir)
        #expect(second.lastPathComponent == "Screenshot (2).png")
        try Data("2".utf8).write(to: second)

        let third = store.uniqueDestinationURL(for: name, in: dir)
        #expect(third.lastPathComponent == "Screenshot (3).png")
    }

    @Test("Moves files cleanly to destination and trashing moves out of directory")
    func movesAndTrashesFiles() throws {
        let staging = try TestFixtures.makeTempDirectory()
        let dest = try TestFixtures.makeTempDirectory()
        var trashedURL: URL?
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: dest)
            if let trashedURL {
                try? FileManager.default.removeItem(at: trashedURL)
            }
        }

        let source = staging.appendingPathComponent("cap.png")
        try Data("payload".utf8).write(to: source)

        let store = DestinationStore()
        let moved = try store.moveToDestination(from: source, toDirectory: dest)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: moved.path))

        trashedURL = try store.trashFile(at: moved)
        #expect(!FileManager.default.fileExists(atPath: moved.path))
    }
}
