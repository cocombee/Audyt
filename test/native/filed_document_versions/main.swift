import Foundation
import PDFKit

func run() throws -> Any {
  let raw = FileHandle.standardInput.readDataToEndOfFile()
  guard let args = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
        let fixture = args["fixtureRoot"] as? String,
        let suite = args["suite"] as? String,
        suite.hasPrefix("com.audyt.disposable-filed-versions."),
        let mode = args["method"] as? String else { throw CocoaError(.fileReadCorruptFile) }
  let root = URL(fileURLWithPath: fixture).resolvingSymlinksInPath().standardizedFileURL
  guard root.lastPathComponent.hasPrefix("audyt-filed-native-"),
        try String(contentsOf: root.appendingPathComponent(".disposable-suite"), encoding: .utf8) == suite,
        let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileReadNoPermission) }
  let manager = FileManager.default
  let source = root.appendingPathComponent("Source"), target = root.appendingPathComponent("Destination")
  let kind = args["kind"] as? String ?? "expense"
  guard ReceiptFiledDocumentStore.families.contains(kind) else { throw CocoaError(.fileReadCorruptFile) }
  func bookmark(_ url: URL) throws -> Data {
    try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
  }
  func savedRoot() throws -> URL {
    guard let grant = defaults.data(forKey: "audyt.setup.\(kind).folder") else { throw CocoaError(.fileReadNoPermission) }
    var stale = false
    return try URL(resolvingBookmarkData: grant, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
  }
  func bytes() throws -> Data {
    guard let encoded = args["bytes"] as? String, let data = Data(base64Encoded: encoded) else { throw CocoaError(.fileReadCorruptFile) }
    return data
  }
  func id() throws -> String {
    guard let id = args["attachmentId"] as? String, !id.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    return id
  }
  switch mode {
  case "inspectPdf":
    guard let pdf = PDFDocument(data: try bytes()), !pdf.isLocked else { throw CocoaError(.fileReadCorruptFile) }
    return (0..<pdf.pageCount).map { index -> [String: Any] in
      let page = pdf.page(at: index)!
      let bounds = page.bounds(for: .mediaBox)
      return ["text": page.string ?? "", "width": bounds.width, "height": bounds.height]
    }
  case "pdfPage":
    guard let index = args["page"] as? Int else { throw CocoaError(.fileReadCorruptFile) }
    let rendered = try DocumentPreviewRenderer.render(bytes(), page: index)
    return ["bytes": rendered.bytes.base64EncodedString(), "pages": rendered.pages]
  case "configure":
    try manager.createDirectory(at: source, withIntermediateDirectories: true)
    try manager.createDirectory(at: target, withIntermediateDirectories: true)
    for family in ReceiptFiledDocumentStore.families {
      defaults.set(try bookmark(source), forKey: "audyt.setup.\(family).folder")
      defaults.set("[{\"type\":\"custom\",\"text\":\"Receipt\"}]", forKey: "audyt.setup.\(family).format")
    }
    guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    return ["configured": true]
  case "load":
    try ReceiptFolderRelocationRecovery.finishPending(defaults: defaults, invalidateRoots: {})
    return defaults.string(forKey: "audyt.setup.\(kind).format") as Any? ?? NSNull()
  case "loadFolder":
    try ReceiptFolderRelocationRecovery.finishPending(defaults: defaults, invalidateRoots: {})
    return try savedRoot().path
  case "saveDocument", "legacy":
    try ReceiptFolderRelocationRecovery.finishPending(defaults: defaults, invalidateRoots: {})
    let destination = try savedRoot()
    let access = destination.startAccessingSecurityScopedResource()
    defer { if access { destination.stopAccessingSecurityScopedResource() } }
    guard let year = args["year"] as? Int, let month = args["month"] as? Int,
          let filename = args["filename"] as? String else { throw CocoaError(.fileReadCorruptFile) }
    let data = try bytes(), attachment = try id()
    let file: URL
    if mode == "legacy" {
      file = try ReceiptDestinationWriter.write(root: destination, year: year, month: month, filename: filename, data: data)
      defaults.set(["path": file.path, "hash": ReceiptDestinationWriter.hash(data)], forKey: ReceiptFiledDocumentStore.latestKey(kind, attachment))
      guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    } else {
      file = try ReceiptFiledDocumentStore.save(kind: kind, attachmentId: attachment, root: destination,
        year: year, month: month, filename: filename, data: data, defaults: defaults,
        generated: args["generated"] as? Bool == true)
    }
    return file.path
  case "readDocument":
    guard let digest = args["expectedSha256"] as? String else { throw CocoaError(.fileReadCorruptFile) }
    let read = try ReceiptFiledDocumentStore.read(attachmentId: try id(), expectedHash: digest, defaults: defaults)
    return ["bytes": read.bytes.base64EncodedString(), "mimeType": read.mimeType]
  case "prepare":
    let manifest = try ReceiptFolderRelocator.prepare(source: source, destination: target)
    var updates = try ReceiptFolderRelocationRecovery.proposedUpdates(kind: "expense", format: "[{\"type\":\"custom\",\"text\":\"Receipt\"}]",
      source: source, destination: target, destinationBookmark: bookmark(target), manifest: manifest, defaults: defaults)
    if args["omitVersions"] as? Bool == true {
      for key in updates.keys.filter({ $0.hasPrefix("audyt.document-version.") }) { updates.removeValue(forKey: key) }
    }
    defaults.set(["oldBookmark": try bookmark(source), "newBookmark": try bookmark(target), "manifest": manifest, "updates": updates],
      forKey: "audyt.setup.expense.relocation")
    guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    return ["files": manifest.count, "updates": updates.count]
  case "commitSetup":
    guard let displayed = args["folderPath"] as? String,
          let year = args["year"] as? Int, let month = args["month"] as? Int,
          let format = args["format"] as? String else { throw CocoaError(.fileReadCorruptFile) }
    try ReceiptFolderRelocationRecovery.finishPending(defaults: defaults, invalidateRoots: {})
    var selection = NamingFolderSelection()
    selection.choose(kind: kind, url: target)
    let selected = try selection.rootForCommit(kind: kind, expectedPath: displayed, savedRoot: savedRoot())
    return try ReceiptFolderSetupCommit.commit(kind: kind, format: format, root: selected,
      year: year, month: month, defaults: defaults, invalidateRoots: {}).path
  case "inspect":
    var roots: [String: String] = [:]
    for family in ReceiptFiledDocumentStore.families {
      if let grant = defaults.data(forKey: "audyt.setup.\(family).folder") {
        var stale = false
        roots[family] = try URL(resolvingBookmarkData: grant, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale).path
      }
    }
    let links = defaults.dictionaryRepresentation().filter { ReceiptFiledDocumentStore.isLinkKey($0.key) }
    return ["roots": roots, "links": links, "pending": defaults.object(forKey: "audyt.setup.expense.relocation") != nil]
  case "cleanup":
    defaults.removePersistentDomain(forName: suite)
    guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    return ["cleaned": true]
  default: throw CocoaError(.fileReadCorruptFile)
  }
}
do {
  let result = try run()
  let data = try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed, .sortedKeys])
  FileHandle.standardOutput.write(data)
} catch {
  FileHandle.standardError.write(Data(error.localizedDescription.utf8))
  exit(1)
}
