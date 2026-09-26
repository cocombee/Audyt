import Foundation

func check(_ condition: Bool, _ message: String) {
  if !condition { fatalError(message) }
}
func expectFailure(line: Int = #line, _ action: () throws -> Void) {
  do { try action(); fatalError("Expected relocation failure at line \(line)") } catch { }
}
let manager = FileManager.default
let root = URL(fileURLWithPath: "/private/tmp/Audyt Folder Move Tests-" + UUID().uuidString)
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }
func folder(_ name: String) throws -> URL {
  let url = root.appendingPathComponent(name)
  try manager.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
func put(_ root: URL, _ relative: String, _ value: String) throws -> URL {
  let url = root.appendingPathComponent(relative)
  try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data(value.utf8).write(to: url)
  return url
}

let source = try folder("Existing Folder")
let destination = try folder("New Folder")
var selection = NamingFolderSelection()
selection.choose(kind: "expense", url: destination)
expectFailure { _ = try selection.rootForCommit(kind: "expense", expectedPath: source.path, savedRoot: source) }
check(try selection.rootForCommit(kind: "expense", expectedPath: destination.path, savedRoot: source).path == ReceiptFolderRelocator.canonical(destination).path, "Save must use the displayed picker proposal")
selection.discard(kind: "expense")
check(try selection.rootForCommit(kind: "expense", expectedPath: source.path, savedRoot: source) == source, "Discard must retain the saved root")
expectFailure { _ = try selection.rootForCommit(kind: "expense", expectedPath: destination.path, savedRoot: source) }
expectFailure { _ = try selection.rootForCommit(kind: "claims", expectedPath: destination.path, savedRoot: nil) }
selection.choose(kind: "claims", url: destination)
check(try selection.rootForCommit(kind: "expense", expectedPath: source.path, savedRoot: source) == source, "Another family's proposal must not redirect saved writes")
let files = ["2026/09. September/invoice.pdf", "2026/09. September/receipts/photo.png", "2026/09. September/receipts/PAID.json"]
for path in files { _ = try put(source, path, path) }
let manifest = try ReceiptFolderRelocator.prepare(source: source, destination: destination)
check(manifest.count == 3, "Complete nested contents must be retained")
for file in files { check(manager.fileExists(atPath: source.appendingPathComponent(file).path), "Preparation deleted a source") }
// Native links use the unchanged relative suffix and checksum after relocation.
for item in manifest {
  check(ReceiptDestinationWriter.hash(try Data(contentsOf: destination.appendingPathComponent(item["relative"]!))) == item["hash"], "Destination hash mismatch")
}
try ReceiptFolderRelocator.cleanup(source: source, destination: destination, manifest: manifest)
try ReceiptFolderRelocator.cleanup(source: source, destination: destination, manifest: manifest) // interrupted cleanup retry
for file in files { check(!manager.fileExists(atPath: source.appendingPathComponent(file).path), "Verified original was not moved") }

let collisionSource = try folder("Collision Source"), collisionTarget = try folder("Collision Target")
_ = try put(collisionSource, "a.pdf", "a"); _ = try put(collisionSource, "z.pdf", "source")
_ = try put(collisionTarget, "z.pdf", "different")
expectFailure { _ = try ReceiptFolderRelocator.prepare(source: collisionSource, destination: collisionTarget) }
check(manager.fileExists(atPath: collisionSource.appendingPathComponent("a.pdf").path), "Conflict removed source")
check(!manager.fileExists(atPath: collisionTarget.appendingPathComponent("a.pdf").path), "Conflict did not preflight all files")
expectFailure { _ = try ReceiptFolderRelocator.prepare(source: collisionSource, destination: collisionSource.appendingPathComponent("nested")) }

let interrupted = try folder("Interrupted Source"), recovery = try folder("Recovery Target")
_ = try put(interrupted, "a.pdf", "original"); _ = try put(interrupted, "b.pdf", "original b")
let pending = try ReceiptFolderRelocator.prepare(source: interrupted, destination: recovery)
_ = try put(interrupted, "b.pdf", "changed externally")
expectFailure { try ReceiptFolderRelocator.cleanup(source: interrupted, destination: recovery, manifest: pending) }
check(manager.fileExists(atPath: interrupted.appendingPathComponent("a.pdf").path), "Cleanup failed without retaining every source")
_ = try put(interrupted, "b.pdf", "original b")
_ = try put(recovery, "a.pdf", "tampered")
expectFailure { try ReceiptFolderRelocator.cleanup(source: interrupted, destination: recovery, manifest: pending) }
check(manager.fileExists(atPath: interrupted.appendingPathComponent("a.pdf").path), "Tampered copy removed source")

let symlinkSource = try folder("Symlink Source")
try manager.createSymbolicLink(at: symlinkSource.appendingPathComponent("external"), withDestinationURL: collisionSource)
expectFailure { _ = try ReceiptFolderRelocator.prepare(source: symlinkSource, destination: try folder("Symlink Destination")) }
let revisions = try folder("Record Revisions")
let oldBytes = Data("old saved output".utf8), newBytes = Data("new edited output".utf8)
let oldHash = ReceiptDestinationWriter.hash(oldBytes), newHash = ReceiptDestinationWriter.hash(newBytes)
let oldFile = try ReceiptDestinationWriter.write(root: revisions, year: 2026, month: 9, filename: "receipt.png", data: oldBytes)
try ReceiptDestinationWriter.verifyRead(Data(contentsOf: oldFile), savedHash: oldHash, expectedHash: oldHash)
let newFile = try ReceiptDestinationWriter.write(root: revisions, year: 2026, month: 9, filename: "receipt.png", data: newBytes, previousPath: oldFile.path, previousHash: oldHash)
check(newFile.path != oldFile.path, "Edited output must preserve the earlier filed version")
try ReceiptDestinationWriter.verifyRead(Data(contentsOf: oldFile), savedHash: oldHash, expectedHash: oldHash)
try ReceiptDestinationWriter.verifyRead(Data(contentsOf: newFile), savedHash: newHash, expectedHash: newHash)
expectFailure { try ReceiptDestinationWriter.verifyRead(Data(contentsOf: newFile), savedHash: newHash, expectedHash: oldHash) }
expectFailure { try ReceiptDestinationWriter.verifyRead(Data(contentsOf: newFile), savedHash: oldHash, expectedHash: oldHash) }
expectFailure { try ReceiptDestinationWriter.verifyRead(newBytes, savedHash: newHash, expectedHash: "invalid") }
let revisedRoot = try folder("Moved Record Revisions")
let revisedManifest = try ReceiptFolderRelocator.prepare(source: revisions, destination: revisedRoot)
try ReceiptFolderRelocator.cleanup(source: revisions, destination: revisedRoot, manifest: revisedManifest)
let editedManifest = revisedManifest.first { $0["hash"] == newHash }!
let movedFile = revisedRoot.appendingPathComponent(editedManifest["relative"]!)
try ReceiptDestinationWriter.verifyRead(Data(contentsOf: movedFile), savedHash: editedManifest["hash"]!, expectedHash: newHash)
expectFailure { try ReceiptDestinationWriter.verifyRead(Data(contentsOf: movedFile), savedHash: editedManifest["hash"]!, expectedHash: oldHash) }
let originalManifest = revisedManifest.first { $0["hash"] == oldHash }!
try ReceiptDestinationWriter.verifyRead(Data(contentsOf: revisedRoot.appendingPathComponent(originalManifest["relative"]!)), savedHash: oldHash, expectedHash: oldHash)
// Exercise the same persisted recovery owner used by MainFlutterWindow.
let suite = "com.audyt.disposable-folder-recovery." + UUID().uuidString
guard var defaults = UserDefaults(suiteName: suite) else { fatalError("Missing test defaults") }
defer { defaults.removePersistentDomain(forName: suite); defaults.synchronize() }
let recoveringSource = try folder("Durable Source"), recoveringTarget = try folder("Durable Target")
let recoveryFiles = ["2026/09. September/expense.png", "Invoices/2026/invoice.pdf", "Claims/2026/receipt.png", "Vouchers/2026/voucher.pdf"]
for relative in recoveryFiles { _ = try put(recoveringSource, relative, relative) }
let recoveryManifest = try ReceiptFolderRelocator.prepare(source: recoveringSource, destination: recoveringTarget)
let oldBookmark = try recoveringSource.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
let newBookmark = try recoveringTarget.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
let oldFormat = "old naming format", newFormat = "new naming format"
var originalLinks: [String: [String: String]] = [:]
var originalBookmarks: [String: Data] = [:]
let familySuffixes = ["expense": "", "invoice": "Invoices", "claims": "Claims", "voucher": "Vouchers"]
for (index, family) in ["expense", "invoice", "claims", "voucher"].enumerated() {
  let folderKey = "audyt.setup.\(family).folder"
  let suffix = familySuffixes[family]!
  let previousRoot = suffix.isEmpty ? recoveringSource : recoveringSource.appendingPathComponent(suffix)
  let previousBookmark = try previousRoot.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
  originalBookmarks[family] = previousBookmark
  defaults.set(previousBookmark, forKey: folderKey)
  let linkKey = "audyt.document.\(family).fictional-record-\(index)"
  let relative = recoveryFiles[index]
  let digest = ReceiptDestinationWriter.hash(try Data(contentsOf: recoveringSource.appendingPathComponent(relative)))
  let original = ["path": recoveringSource.appendingPathComponent(relative).path, "hash": digest]
  originalLinks[linkKey] = original
  defaults.set(original, forKey: linkKey)
}
defaults.set(oldFormat, forKey: "audyt.setup.expense.format")
// Use the production mapping owner, including nested sibling bookmarks.
let updates = try ReceiptFolderRelocationRecovery.proposedUpdates(kind: "expense", format: newFormat,
  source: recoveringSource, destination: recoveringTarget, destinationBookmark: newBookmark,
  manifest: recoveryManifest, defaults: defaults)
for (key, record) in originalLinks {
  check(defaults.dictionary(forKey: key) as? [String: String] == record, "Proposal changed live links before commit")
  guard let proposed = updates[key] as? [String: String], let path = proposed["path"] else { fatalError("A path alias silently skipped a linked document") }
  let originalPath = ReceiptFolderRelocator.canonical(URL(fileURLWithPath: record["path"]!)).path
  let suffix = String(originalPath.dropFirst(ReceiptFolderRelocator.canonical(recoveringSource).path.count + 1))
  check(path == ReceiptFolderRelocator.canonical(recoveringTarget).appendingPathComponent(suffix).path,
    "A linked document lost its relative suffix")
  check(proposed["hash"] == record["hash"], "Relocation changed a saved document hash")
}
let missingLink = "audyt.document.claims.fictional-missing"
defaults.set(["path": recoveringSource.appendingPathComponent("missing.pdf").path, "hash": oldHash], forKey: missingLink)
expectFailure { _ = try ReceiptFolderRelocationRecovery.proposedUpdates(kind: "expense", format: newFormat,
  source: recoveringSource, destination: recoveringTarget, destinationBookmark: newBookmark,
  manifest: recoveryManifest, defaults: defaults) }
defaults.removeObject(forKey: missingLink)
let pendingKey = "audyt.setup.expense.relocation"
let durable: [String: Any] = ["oldBookmark": oldBookmark, "newBookmark": newBookmark, "manifest": recoveryManifest, "updates": updates]
defaults.set(durable, forKey: pendingKey)
check(defaults.synchronize(), "Proposal must persist")
defaults = UserDefaults(suiteName: suite)! // Reopen persisted settings, not an in-memory fixture map.
var invalidations = 0
func finishRecovery() throws {
  try ReceiptFolderRelocationRecovery.finish(kind: "expense", defaults: defaults) { invalidations += 1 }
}
func checkOldLinks() {
  check(defaults.string(forKey: "audyt.setup.expense.format") == oldFormat, "Failed recovery changed naming format")
  for family in ["expense", "invoice", "claims", "voucher"] {
    check(defaults.data(forKey: "audyt.setup.\(family).folder") == originalBookmarks[family], "Failed recovery redirected a shared root")
  }
  for (key, record) in originalLinks {
    check(defaults.dictionary(forKey: key) as? [String: String] == record, "Failed recovery rewrote a document link")
  }
  check(invalidations == 0, "Failure invalidated roots before validating copies")
  for relative in recoveryFiles { check(manager.fileExists(atPath: recoveringSource.appendingPathComponent(relative).path), "Failure deleted an original") }
  check(defaults.object(forKey: pendingKey) != nil, "Failure lost the durable proposal")
}
_ = try put(recoveringTarget, recoveryFiles[3], "external destination change")
expectFailure { try finishRecovery() }
checkOldLinks()
_ = try put(recoveringTarget, recoveryFiles[3], recoveryFiles[3])
_ = try put(recoveringSource, recoveryFiles[2], "external source change")
expectFailure { try finishRecovery() }
checkOldLinks()
_ = try put(recoveringSource, recoveryFiles[2], recoveryFiles[2])
var incomplete = durable
incomplete["updates"] = [String: Any]()
defaults.set(incomplete, forKey: pendingKey)
check(defaults.synchronize(), "Incomplete fixture must persist")
expectFailure { try finishRecovery() }
checkOldLinks()
var omittedLinkUpdates = updates
omittedLinkUpdates.removeValue(forKey: originalLinks.keys.sorted().first!)
incomplete["updates"] = omittedLinkUpdates
defaults.set(incomplete, forKey: pendingKey)
check(defaults.synchronize(), "Missing-link fixture must persist")
expectFailure { try finishRecovery() }
checkOldLinks()
let firstLink = originalLinks.keys.sorted().first!
var missingSibling = updates
missingSibling.removeValue(forKey: "audyt.setup.invoice.folder")
var wrongRoot = updates
wrongRoot["audyt.setup.expense.folder"] = oldBookmark
var wrongDocument = updates
wrongDocument[firstLink] = originalLinks[firstLink]
var wrongHash = updates
var invalidRecord = updates[firstLink] as! [String: String]
invalidRecord["hash"] = String(repeating: "0", count: 64)
wrongHash[firstLink] = invalidRecord
var extraSetting = updates
extraSetting["unrelated.preference"] = "must not change"
for corruptUpdates in [missingSibling, wrongRoot, wrongDocument, wrongHash, extraSetting] {
  incomplete["updates"] = corruptUpdates
  defaults.set(incomplete, forKey: pendingKey)
  check(defaults.synchronize(), "Corrupt update fixture must persist")
  expectFailure { try finishRecovery() }
  checkOldLinks()
}
defaults.set(["manifest": recoveryManifest], forKey: pendingKey)
check(defaults.synchronize(), "Malformed fixture must persist")
expectFailure { try finishRecovery() }
checkOldLinks()
defaults.set(durable, forKey: pendingKey)
check(defaults.synchronize(), "Restored proposal must persist")
try finishRecovery()
check(invalidations == 1, "Success must invalidate all cached roots")
defaults = UserDefaults(suiteName: suite)!
check(defaults.object(forKey: pendingKey) == nil, "Completed recovery retained pending state")
check(defaults.string(forKey: "audyt.setup.expense.format") == newFormat, "Naming format did not survive recovery")
for (key, value) in updates {
  if let bookmark = value as? Data { check(defaults.data(forKey: key) == bookmark, "Saved root did not survive reopen") }
  if let link = value as? [String: String] {
    check(defaults.dictionary(forKey: key) as? [String: String] == link, "Saved document link did not survive reopen")
    try ReceiptDestinationWriter.verifyRead(Data(contentsOf: URL(fileURLWithPath: link["path"]!)), savedHash: link["hash"]!, expectedHash: link["hash"]!)
  }
}
for relative in recoveryFiles { check(!manager.fileExists(atPath: recoveringSource.appendingPathComponent(relative).path), "Committed move retained a verified original") }
for (family, suffix) in familySuffixes {
  var stale = false
  let saved = defaults.data(forKey: "audyt.setup.\(family).folder")!
  let resolved = try URL(resolvingBookmarkData: saved, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
  let expectedRoot = suffix.isEmpty ? recoveringTarget : recoveringTarget.appendingPathComponent(suffix)
  check(ReceiptFolderRelocator.canonical(resolved).path == ReceiptFolderRelocator.canonical(expectedRoot).path, "A nested family root lost its relative suffix")
}
try finishRecovery()
check(invalidations == 1, "Completed retry must not recommit")
// Reconstruct a crash after saved links/cleanup but before manifest removal.
defaults.set(durable, forKey: pendingKey)
check(defaults.synchronize(), "Interrupted completion fixture must persist")
defaults = UserDefaults(suiteName: suite)!
try finishRecovery()
check(invalidations == 2, "Interrupted completion should safely replay once")
check(defaults.object(forKey: pendingKey) == nil, "Replayed completion did not clear its manifest")

for invalidRelative in ["", ".", "../a.pdf", "a//b.pdf", "a/./b.pdf", "a\\b.pdf", "/a.pdf"] {
  expectFailure { try ReceiptFolderRelocator.verifyPrepared(source: collisionSource, destination: collisionTarget, manifest: [["relative": invalidRelative, "hash": oldHash]]) }
}
expectFailure { try ReceiptFolderRelocator.verifyPrepared(source: collisionSource, destination: collisionSource, manifest: []) }
expectFailure { try ReceiptFolderRelocator.verifyPrepared(source: collisionSource, destination: collisionTarget, manifest: [["relative": "z.pdf", "hash": "invalid"]]) }

print("PASS: folder selection, nested moves, hashes, source preservation, cleanup retry, conflict preflight, nested roots, mutation, tampering, symlinks, exact record-version reads, durable four-family recovery, failed-recovery link preservation, malformed proposal rejection and verified reopen/retry")
