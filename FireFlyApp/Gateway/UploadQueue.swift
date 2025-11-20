import Foundation

public struct UploadPackage: Codable {
    public let id: UUID
    public let session: SessionMeta
    public let trials: [Trial]
    public let results: Results

    public init(id: UUID, session: SessionMeta, trials: [Trial], results: Results) {
        self.id = id
        self.session = session
        self.trials = trials
        self.results = results
    }

}

public final class UploadQueue {
    private let storageURL: URL?
    private var packages: [UploadPackage]
    private let queue = DispatchQueue(label: "UploadQueue")

    public static var disabled: UploadQueue { UploadQueue(storageURL: nil) }

    public init(storageURL: URL? = UploadQueue.defaultURL()) {
        self.storageURL = storageURL
        self.packages = UploadQueue.load(from: storageURL)
    }

    public func enqueue(_ package: UploadPackage) {
        queue.sync {
            packages.append(package)
            persist()
        }
    }

    public func peek() -> UploadPackage? {
        queue.sync { packages.first }
    }

    public func pop() -> UploadPackage? {
        queue.sync {
            guard !packages.isEmpty else { return nil }
            let pkg = packages.removeFirst()
            persist()
            return pkg
        }
    }

    public func all() -> [UploadPackage] {
        queue.sync { packages }
    }

    public func clear() {
        queue.sync {
            packages.removeAll()
            persist()
        }
    }

    private func persist() {
        guard let storageURL else { return }
        do {
            let data = try JSONEncoder().encode(packages)
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("UploadQueue persist error: \(error)")
        }
    }

    private static func load(from url: URL?) -> [UploadPackage] {
        guard let url else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([UploadPackage].self, from: data)) ?? []
    }

    public static func defaultURL() -> URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory.appendingPathComponent("firefly-upload-queue.json")
    }
}
