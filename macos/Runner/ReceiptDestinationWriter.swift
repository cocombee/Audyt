import Foundation
import CryptoKit

struct ReceiptDestinationWriter {
  /// The selected root is manual; only this dated hierarchy is generated.
  static func monthFolderName(year: Int, month: Int) throws -> String {
    guard (1900...9999).contains(year), (1...12).contains(month) else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    return String(format: "%02d. %@ %d", month, months[month - 1], year)
  }
  static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func verifyRead(_ data: Data, savedHash: String, expectedHash: String) throws {
    guard expectedHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
          savedHash == expectedHash else {
      throw NSError(domain: "The filed document does not match this saved record version. Reconnect the matching file.", code: 1)
    }
    guard hash(data) == savedHash else {
      throw NSError(domain: "The linked file changed. Its saved checksum does not match.", code: 1)
    }
  }

  static func write(root: URL, year: Int, month: Int, filename: String, data: Data,
                    previousPath: String? = nil, previousHash: String? = nil,
                    preserveExistingName: Bool = true) throws -> URL {
    guard (1900...9999).contains(year), (1...12).contains(month),
          !filename.isEmpty, filename != ".", filename != "..",
          !filename.contains("/"), !filename.contains("\\"),
          !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
          !data.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
    let base = root.resolvingSymlinksInPath().standardizedFileURL
    let directory = base.appendingPathComponent(String(year), isDirectory: true)
      .appendingPathComponent(try monthFolderName(year: year, month: month), isDirectory: true)
    guard directory.resolvingSymlinksInPath().path.hasPrefix(base.path + "/") else { throw CocoaError(.fileWriteNoPermission) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let previousPath, let previousHash {
      let previous = URL(fileURLWithPath: previousPath).standardizedFileURL
      if previous.path.hasPrefix(directory.path + "/"),
         previous.deletingLastPathComponent().path == directory.path,
         previous.resolvingSymlinksInPath().path == previous.path,
         previous.pathExtension == (filename as NSString).pathExtension,
         FileManager.default.fileExists(atPath: previous.path) {
        guard hash(try Data(contentsOf: previous)) == previousHash else { throw CocoaError(.fileWriteFileExists) }
        // A saved record version keeps its exact bytes. Only identical output
        // can reuse a filed path; edits receive the existing collision suffix.
        let stem = (filename as NSString).deletingPathExtension
        let suffix = "^" + NSRegularExpression.escapedPattern(for: stem) + "(?:-[0-9]+)?$"
        let sameName = previous.deletingPathExtension().lastPathComponent.range(of: suffix, options: .regularExpression) != nil
        if hash(data) == previousHash && (preserveExistingName || sameName) { return previous }
      }
    }
    let stem = (filename as NSString).deletingPathExtension
    let ext = (filename as NSString).pathExtension
    let staging = directory.appendingPathComponent(".audyt-\(UUID().uuidString).tmp")
    try data.write(to: staging, options: .atomic)
    defer { try? FileManager.default.removeItem(at: staging) }
    for suffix in 0..<10000 {
      let name = suffix == 0 ? filename : "\(stem)-\(suffix + 1)" + (ext.isEmpty ? "" : ".\(ext)")
      let destination = directory.appendingPathComponent(name)
      do {
        try FileManager.default.moveItem(at: staging, to: destination)
        guard try Data(contentsOf: destination) == data else { throw CocoaError(.fileWriteUnknown) }
        return destination
      } catch let error as CocoaError where error.code == .fileWriteFileExists {
        continue
      }
    }
    throw CocoaError(.fileWriteFileExists)
  }
}

/// Version-addressed filed copies complement the legacy latest-document link.
/// SQLite snapshots identify their exact output by attachment ID and checksum.
struct ReceiptFiledDocumentStore {
  static let families = ["expense", "invoice", "voucher", "claims"]
  static func isLinkKey(_ key: String) -> Bool {
    key.hasPrefix("audyt.document.") || key.hasPrefix("audyt.document-version.")
  }
  static func latestKey(_ kind: String, _ id: String) -> String { "audyt.document.\(kind).\(id)" }
  static func versionKey(_ kind: String, _ id: String, _ hash: String) -> String {
    "audyt.document-version.\(kind).\(id).\(hash)"
  }
  static func validHash(_ hash: String) -> Bool {
    hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
  }
  static func record(_ key: String, defaults: UserDefaults) throws -> [String: String]? {
    guard let raw = defaults.object(forKey: key) else { return nil }
    guard let record = raw as? [String: String], let path = record["path"], !path.isEmpty,
          let hash = record["hash"], validHash(hash) else { throw CocoaError(.fileReadCorruptFile) }
    return record
  }
  static func verifiedFile(_ record: [String: String], root: URL, expectedHash: String) throws -> URL {
    guard let path = record["path"], let hash = record["hash"], validHash(hash), hash == expectedHash else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let file = URL(fileURLWithPath: path)
    guard ReceiptFolderRelocator.within(ReceiptFolderRelocator.canonical(file).path,
                                        ReceiptFolderRelocator.canonical(root).path),
          ReceiptFolderRelocator.canonical(file).path != ReceiptFolderRelocator.canonical(root).path else {
      throw CocoaError(.fileReadNoPermission)
    }
    try ReceiptDestinationWriter.verifyRead(Data(contentsOf: file), savedHash: hash, expectedHash: expectedHash)
    return file
  }
  static func save(kind: String, attachmentId: String, root: URL, year: Int, month: Int,
                   filename: String, data: Data, defaults: UserDefaults,
                   generated: Bool = false) throws -> URL {
    guard families.contains(kind), !attachmentId.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
    if generated {
      guard kind == "invoice", attachmentId.hasPrefix("generated:"),
            filename.lowercased().hasSuffix(".pdf"), data.starts(with: Data("%PDF-".utf8)) else {
        throw CocoaError(.fileWriteInvalidFileName)
      }
    }
    // Recreate a missing Audyt-owned output from its committed bytes. An
    // altered file, invalid link or manual original must still fail validation.
    func verifyOrMissing(_ record: [String: String], _ expectedHash: String) throws -> URL? {
      if generated, let path = record["path"], record["hash"] == expectedHash {
        let file = URL(fileURLWithPath: path)
        let canonical = ReceiptFolderRelocator.canonical(file).path
        let base = ReceiptFolderRelocator.canonical(root).path
        guard canonical != base, ReceiptFolderRelocator.within(canonical, base) else {
          throw CocoaError(.fileReadNoPermission)
        }
        if !FileManager.default.fileExists(atPath: path) { return nil }
      }
      return try verifiedFile(record, root: root, expectedHash: expectedHash)
    }
    let latest = latestKey(kind, attachmentId), digest = ReceiptDestinationWriter.hash(data)
    let version = versionKey(kind, attachmentId, digest)
    let previous = try record(latest, defaults: defaults)
    var previousVersion: String?
    if let previous {
      guard let previousHash = previous["hash"], validHash(previousHash) else { throw CocoaError(.fileReadCorruptFile) }
      _ = try verifyOrMissing(previous, previousHash)
      previousVersion = versionKey(kind, attachmentId, previousHash)
      if let indexed = try record(previousVersion!, defaults: defaults) {
        _ = try verifyOrMissing(indexed, previousHash)
      }
    }
    let file: URL
    if let indexed = try record(version, defaults: defaults) {
      let existing = try verifyOrMissing(indexed, digest)
      file = try ReceiptDestinationWriter.write(root: root, year: year, month: month, filename: filename,
        data: data, previousPath: existing?.path, previousHash: digest, preserveExistingName: !generated)
    } else {
      file = try ReceiptDestinationWriter.write(root: root, year: year, month: month, filename: filename,
        data: data, previousPath: previous?["path"], previousHash: previous?["hash"], preserveExistingName: !generated)
    }
    if let previousVersion, defaults.object(forKey: previousVersion) == nil { defaults.set(previous, forKey: previousVersion) }
    let record = ["path": file.path, "hash": digest]
    defaults.set(record, forKey: version)
    defaults.set(record, forKey: latest)
    guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    return file
  }
  static func read(attachmentId: String, expectedHash: String, defaults: UserDefaults,
                   invalidateRoots: () -> Void = {}) throws -> (bytes: Data, mimeType: String) {
    guard !attachmentId.isEmpty, validHash(expectedHash) else { throw CocoaError(.fileReadCorruptFile) }
    try ReceiptFolderRelocationRecovery.finishPending(defaults: defaults, invalidateRoots: invalidateRoots)
    var versionMismatch = false
    for family in families {
      for key in [versionKey(family, attachmentId, expectedHash), latestKey(family, attachmentId)] {
        guard let record = try record(key, defaults: defaults), let digest = record["hash"] else { continue }
        guard digest == expectedHash else { versionMismatch = true; continue }
        guard let bookmark = defaults.data(forKey: "audyt.setup.\(family).folder") ??
          (family == "expense" ? defaults.data(forKey: "audyt.namingFolderBookmark") : nil) else { continue }
        var stale = false
        let root = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        let file = try verifiedFile(record, root: root, expectedHash: expectedHash)
        let mime = file.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/" + file.pathExtension.lowercased()
        let bytes = try Data(contentsOf: file)
        try ReceiptDestinationWriter.verifyRead(bytes, savedHash: digest, expectedHash: expectedHash)
        return (bytes, mime)
      }
    }
    throw NSError(domain: versionMismatch
      ? "The filed document does not match this saved record version. Reconnect the matching file."
      : "The linked document is unavailable on this device. Reconnect its original folder.", code: 1)
  }
}

/// A picker proposal is never a saved destination. The form must commit the
/// same displayed path; a stale proposal cannot silently select another root.
struct NamingFolderSelection {
  private var proposals: [String: URL] = [:]

  mutating func choose(kind: String, url: URL) {
    proposals[kind] = url.resolvingSymlinksInPath().standardizedFileURL
  }

  mutating func discard(kind: String) { proposals.removeValue(forKey: kind) }

  func rootForCommit(kind: String, expectedPath: String, savedRoot: URL?) throws -> URL {
    guard !expectedPath.isEmpty, let root = proposals[kind] ?? savedRoot,
          ReceiptFolderRelocator.canonical(URL(fileURLWithPath: expectedPath)).path == ReceiptFolderRelocator.canonical(root).path else {
      throw NSError(domain: "The folder selection changed. Choose your destination again before saving.", code: 1)
    }
    return root
  }
}

/// Preparation leaves all source bytes intact. Commit updates grants/links before
/// cleanup; its durable manifest makes an interrupted cleanup safe to retry.
struct ReceiptFolderRelocator {
  static func canonical(_ input: URL) -> URL {
    var ancestor = input.standardizedFileURL
    var components: [String] = []
    while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
      components.insert(ancestor.lastPathComponent, at: 0)
      ancestor.deleteLastPathComponent()
    }
    return components.reduce(ancestor.resolvingSymlinksInPath().standardizedFileURL) { $0.appendingPathComponent($1) }
  }

  static func within(_ path: String, _ root: String) -> Bool {
    path == root || path.hasPrefix(root + "/")
  }

  static func prepare(source: URL, destination: URL) throws -> [[String: String]] {
    let manager = FileManager.default
    let old = canonical(source)
    let new = canonical(destination)
    guard (try source.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
    if old.path == new.path { return [] }
    guard !within(new.path, old.path), !within(old.path, new.path),
          old.resolvingSymlinksInPath().path == old.path,
          new.resolvingSymlinksInPath().path == new.path else {
      throw NSError(domain: "Choose a separate destination outside the existing folder. Symlink roots are not supported.", code: 1)
    }
    var enumerationError: Error?
    guard let files = manager.enumerator(at: old, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else {
      throw CocoaError(.fileReadNoPermission)
    }
    var manifest: [[String: String]] = []
    while let file = files.nextObject() as? URL {
      let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
      guard values.isSymbolicLink != true else { throw NSError(domain: "A linked folder contains a symlink. Existing files were preserved.", code: 1) }
      if values.isRegularFile != true { continue }
      let canonicalFile = canonical(file)
      guard within(canonicalFile.path, old.path) else { throw CocoaError(.fileReadNoPermission) }
      let relative = String(canonicalFile.path.dropFirst(old.path.count + 1))
      let target = new.appendingPathComponent(relative)
      guard canonical(target).path == target.path else { throw CocoaError(.fileWriteNoPermission) }
      let digest = ReceiptDestinationWriter.hash(try Data(contentsOf: file))
      if manager.fileExists(atPath: target.path),
         ReceiptDestinationWriter.hash(try Data(contentsOf: target)) != digest {
        throw NSError(domain: "A different file already exists at \(relative). Existing files were preserved.", code: 1)
      }
      manifest.append(["relative": relative, "hash": digest])
    }
    if let error = enumerationError { throw error }
    // Preflight the complete tree before creating any destination documents.
    for entry in manifest {
      let file = old.appendingPathComponent(entry["relative"]!)
      let target = new.appendingPathComponent(entry["relative"]!)
      try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      if !manager.fileExists(atPath: target.path) {
        let partial = target.deletingLastPathComponent().appendingPathComponent(".audyt-relocation-" + UUID().uuidString)
        defer { try? manager.removeItem(at: partial) }
        try manager.copyItem(at: file, to: partial)
        guard ReceiptDestinationWriter.hash(try Data(contentsOf: partial)) == entry["hash"] else { throw CocoaError(.fileWriteUnknown) }
        try manager.moveItem(at: partial, to: target)
      }
      guard ReceiptDestinationWriter.hash(try Data(contentsOf: target)) == entry["hash"] else { throw CocoaError(.fileWriteUnknown) }
    }
    return manifest
  }

  static func verifyPrepared(source: URL, destination: URL, manifest: [[String: String]]) throws {
    let source = canonical(source)
    let destination = canonical(destination)
    let manager = FileManager.default
    guard !within(source.path, destination.path), !within(destination.path, source.path) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    var paths = Set<String>()
    // Validate all remaining sources and all destinations before removing any.
    for entry in manifest {
      guard let relative = entry["relative"], let digest = entry["hash"],
            !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\"),
            !relative.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
            digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
            paths.insert(relative).inserted else { throw CocoaError(.fileReadCorruptFile) }
      let target = destination.appendingPathComponent(relative)
      let original = source.appendingPathComponent(relative)
      guard canonical(target).path == target.path,
            ReceiptDestinationWriter.hash(try Data(contentsOf: target)) == digest else { throw CocoaError(.fileWriteUnknown) }
      if manager.fileExists(atPath: original.path) {
        guard canonical(original).path == original.path,
              ReceiptDestinationWriter.hash(try Data(contentsOf: original)) == digest else {
          throw NSError(domain: "A source changed during relocation. Existing files were preserved for review.", code: 1)
        }
      }
    }
  }

  static func cleanup(source: URL, destination: URL, manifest: [[String: String]]) throws {
    try verifyPrepared(source: source, destination: destination, manifest: manifest)
    let source = canonical(source)
    let manager = FileManager.default
    for entry in manifest {
      let original = source.appendingPathComponent(entry["relative"]!)
      if manager.fileExists(atPath: original.path) { try manager.removeItem(at: original) }
    }
    // Remove only empty child folders; never delete unrelated new source files.
    let dirs = manager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil)?.allObjects.compactMap { $0 as? URL } ?? []
    for directory in dirs.sorted(by: { $0.path.count > $1.path.count }) {
      if (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
         (try? manager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
        try manager.removeItem(at: directory)
      }
    }
  }
}

/// A restart resumes the exact durable proposal. Verify the copied tree before
/// switching saved grants/links; failure leaves the manifest available to retry.
struct ReceiptFolderRelocationRecovery {
  static func finishPending(defaults: UserDefaults, invalidateRoots: () -> Void) throws {
    for family in ReceiptFiledDocumentStore.families {
      try finish(kind: family, defaults: defaults, invalidateRoots: invalidateRoots)
    }
  }

  private static func validateUpdates(kind: String, updates: [String: Any], source: URL,
                                      destination: URL, manifest: [[String: String]], defaults: UserDefaults) throws {
    let families = ["expense", "invoice", "voucher", "claims"]
    let old = ReceiptFolderRelocator.canonical(source)
    let new = ReceiptFolderRelocator.canonical(destination)
    guard families.contains(kind),
          let format = updates["audyt.setup.\(kind).format"] as? String, !format.isEmpty,
          updates["audyt.setup.\(kind).folder"] is Data else { throw CocoaError(.fileReadCorruptFile) }
    let hashes = Dictionary(uniqueKeysWithValues: manifest.map { ($0["relative"]!, $0["hash"]!) })
    func bookmarkPath(_ data: Data) throws -> String {
      var stale = false
      let root = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
      return ReceiptFolderRelocator.canonical(root).path
    }
    // Every root served by the old tree needs its corresponding saved grant.
    for family in families {
      let key = "audyt.setup.\(family).folder"
      let expected: String?
      if family == kind { expected = new.path }
      else if let current = defaults.data(forKey: key) {
        let path = try bookmarkPath(current)
        if ReceiptFolderRelocator.within(path, old.path) {
          expected = new.path + String(path.dropFirst(old.path.count))
        } else if ReceiptFolderRelocator.within(path, new.path) { expected = path }
        else { expected = nil }
      } else { expected = nil }
      if let expected {
        // An already-committed sibling may be absent from a later proposal.
        if updates[key] == nil, let current = defaults.data(forKey: key),
           try bookmarkPath(current) == expected { continue }
        guard let data = updates[key] as? Data, try bookmarkPath(data) == expected else { throw CocoaError(.fileReadCorruptFile) }
      } else if updates[key] != nil { throw CocoaError(.fileReadCorruptFile) }
    }
    // Missing link updates must not permit deleting the linked originals.
    for (key, value) in defaults.dictionaryRepresentation() where ReceiptFiledDocumentStore.isLinkKey(key) {
      guard var record = value as? [String: String], let path = record["path"] else { continue }
      let resolved = ReceiptFolderRelocator.canonical(URL(fileURLWithPath: path)).path
      guard ReceiptFolderRelocator.within(resolved, old.path), resolved != old.path else { continue }
      let relative = String(resolved.dropFirst(old.path.count + 1))
      guard let digest = hashes[relative], digest == record["hash"] else { throw CocoaError(.fileReadCorruptFile) }
      record["path"] = new.appendingPathComponent(relative).path
      guard updates[key] as? [String: String] == record else { throw CocoaError(.fileReadCorruptFile) }
    }
    for (key, value) in updates {
      if key == "audyt.setup.\(kind).format" { continue }
      if families.contains(where: { key == "audyt.setup.\($0).folder" }) { continue }
      guard ReceiptFiledDocumentStore.isLinkKey(key), let record = value as? [String: String],
            let path = record["path"],
            let previous = defaults.dictionary(forKey: key) as? [String: String],
            let previousPath = previous["path"] else { throw CocoaError(.fileReadCorruptFile) }
      let resolved = ReceiptFolderRelocator.canonical(URL(fileURLWithPath: path)).path
      guard ReceiptFolderRelocator.within(resolved, new.path), resolved != new.path,
            resolved == path else { throw CocoaError(.fileReadCorruptFile) }
      let relative = String(resolved.dropFirst(new.path.count + 1))
      let previousResolved = ReceiptFolderRelocator.canonical(URL(fileURLWithPath: previousPath)).path
      var expected = previous
      expected["path"] = path
      guard let digest = hashes[relative], digest == record["hash"], expected == record,
            previousResolved == old.appendingPathComponent(relative).path || previousResolved == path else { throw CocoaError(.fileReadCorruptFile) }
    }
  }

  static func proposedUpdates(kind: String, format: String, source: URL,
                              destination: URL, destinationBookmark: Data,
                              manifest: [[String: String]], defaults: UserDefaults) throws -> [String: Any] {
    let old = ReceiptFolderRelocator.canonical(source)
    let new = ReceiptFolderRelocator.canonical(destination)
    try ReceiptFolderRelocator.verifyPrepared(source: old, destination: new, manifest: manifest)
    let hashes = Dictionary(uniqueKeysWithValues: manifest.map { ($0["relative"]!, $0["hash"]!) })
    var updates: [String: Any] = ["audyt.setup.\(kind).folder": destinationBookmark,
                                  "audyt.setup.\(kind).format": format]
    for (key, value) in defaults.dictionaryRepresentation() where ReceiptFiledDocumentStore.isLinkKey(key) {
      guard var record = value as? [String: String], let path = record["path"] else { continue }
      let resolvedPath = ReceiptFolderRelocator.canonical(URL(fileURLWithPath: path)).path
      guard ReceiptFolderRelocator.within(resolvedPath, old.path), resolvedPath != old.path else { continue }
      let relative = String(resolvedPath.dropFirst(old.path.count + 1))
      guard let digest = hashes[relative], digest == record["hash"] else {
        throw NSError(domain: "A linked document is missing or changed at \(relative). Existing files and settings were preserved.", code: 1)
      }
      record["path"] = new.appendingPathComponent(relative).path
      updates[key] = record
    }
    // A shared root can contain separate transaction-family destinations.
    for sibling in ["expense", "invoice", "voucher", "claims"] {
      if let bookmark = defaults.data(forKey: "audyt.setup.\(sibling).folder") {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        let current = ReceiptFolderRelocator.canonical(url)
        if ReceiptFolderRelocator.within(current.path, old.path) {
          let relative = current.path == old.path ? "" : String(current.path.dropFirst(old.path.count + 1))
          let next = relative.isEmpty ? new : new.appendingPathComponent(relative)
          try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
          updates["audyt.setup.\(sibling).folder"] = try next.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
      }
    }
    return updates
  }

  static func finish(kind: String, defaults: UserDefaults,
                     invalidateRoots: () -> Void) throws {
    let key = "audyt.setup.\(kind).relocation"
    guard defaults.object(forKey: key) != nil else { return }
    guard let pending = defaults.dictionary(forKey: key),
          let oldBookmark = pending["oldBookmark"] as? Data,
          let newBookmark = pending["newBookmark"] as? Data,
          let manifest = pending["manifest"] as? [[String: String]],
          let updates = pending["updates"] as? [String: Any] else {
      throw CocoaError(.fileReadCorruptFile)
    }
    var stale = false
    let old = try URL(resolvingBookmarkData: oldBookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    let new = try URL(resolvingBookmarkData: newBookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    let oldAccess = old.startAccessingSecurityScopedResource()
    let newAccess = new.startAccessingSecurityScopedResource()
    defer {
      if oldAccess { old.stopAccessingSecurityScopedResource() }
      if newAccess { new.stopAccessingSecurityScopedResource() }
    }
    try ReceiptFolderRelocator.verifyPrepared(source: old, destination: new, manifest: manifest)
    try validateUpdates(kind: kind, updates: updates, source: old, destination: new, manifest: manifest, defaults: defaults)
    for (name, value) in updates { defaults.set(value, forKey: name) }
    guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    invalidateRoots()
    try ReceiptFolderRelocator.cleanup(source: old, destination: new, manifest: manifest)
    defaults.removeObject(forKey: key)
    guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
  }
}

/// Commit the displayed file-setup destination. The window owns picker
/// proposals; this owner performs the same durable move for native requests
/// and the isolated file-backed verification fixture.
struct ReceiptFolderSetupCommit {
  static func commit(kind: String, format: String, root: URL, year: Int, month: Int,
                     defaults: UserDefaults, invalidateRoots: () -> Void) throws -> URL {
    guard ReceiptFiledDocumentStore.families.contains(kind), (1900...9999).contains(year),
          (1...12).contains(month),
          let blocks = try JSONSerialization.jsonObject(with: Data(format.utf8)) as? [[String: Any]],
          !blocks.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    try ReceiptFolderRelocationRecovery.finishPending(defaults: defaults, invalidateRoots: invalidateRoots)
    let access = root.startAccessingSecurityScopedResource()
    defer { if access { root.stopAccessingSecurityScopedResource() } }
    let destination = root.appendingPathComponent(String(year), isDirectory: true)
      .appendingPathComponent(try ReceiptDestinationWriter.monthFolderName(year: year, month: month), isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let bookmark = try root.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    let oldBookmark = defaults.data(forKey: "audyt.setup.\(kind).folder") ??
      (kind == "expense" ? defaults.data(forKey: "audyt.namingFolderBookmark") : nil)
    var updates: [String: Any] = ["audyt.setup.\(kind).folder": bookmark,
                                  "audyt.setup.\(kind).format": format]
    if let oldBookmark {
      var stale = false
      let old = try URL(resolvingBookmarkData: oldBookmark, options: [.withSecurityScope],
                        relativeTo: nil, bookmarkDataIsStale: &stale).resolvingSymlinksInPath().standardizedFileURL
      if old.path != root.standardizedFileURL.path {
        let oldAccess = old.startAccessingSecurityScopedResource()
        defer { if oldAccess { old.stopAccessingSecurityScopedResource() } }
        let manifest = try ReceiptFolderRelocator.prepare(source: old, destination: root)
        updates = try ReceiptFolderRelocationRecovery.proposedUpdates(kind: kind, format: format,
          source: old, destination: root, destinationBookmark: bookmark, manifest: manifest, defaults: defaults)
        defaults.set(["oldBookmark": oldBookmark, "newBookmark": bookmark,
                      "manifest": manifest, "updates": updates], forKey: "audyt.setup.\(kind).relocation")
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        try ReceiptFolderRelocationRecovery.finishPending(defaults: defaults, invalidateRoots: invalidateRoots)
      }
    }
    for (key, value) in updates { defaults.set(value, forKey: key) }
    guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    invalidateRoots()
    return destination
  }
}
