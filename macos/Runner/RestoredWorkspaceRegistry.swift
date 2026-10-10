import Foundation
import SQLite3

/// Device-local recovery copies only. Entries never confer business permissions.
final class RestoredWorkspaceRegistry {
  struct Entry: Codable {
    let version: Int
    let id: String
    let businessId: String
    let name: String
    let createdAt: String
    let baselineAuditSequence: Int64?
    let markerExpired: Bool?
  }
  let root: URL
  private let manager = FileManager.default
  private let pendingName = ".audyt-restore-pending"
  private let pendingData = Data("Audyt Restore Pending v1".utf8)
  init(root: URL) { self.root = root.standardizedFileURL }
  private func failure() -> NSError {
    NSError(domain: "The restored workspace is unavailable or needs recovery.", code: 1)
  }
  private func checkRoot(create: Bool = false) throws {
    // Check before creating, so a replaced/symlinked root receives no writes.
    guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else { throw failure() }
    if create { try manager.createDirectory(at: root, withIntermediateDirectories: true) }
    guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.path,
          try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw failure() }
  }
  func prepare() throws -> URL {
    try checkRoot(create: true)
    let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: folder, withIntermediateDirectories: false)
    do {
      let pending = folder.appendingPathComponent(pendingName)
      try pendingData.write(to: pending, options: .atomic)
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pending.path)
    } catch {
      try? manager.removeItem(at: folder)
      throw error
    }
    return folder.appendingPathComponent("ledger.sqlite")
  }
  /// Remove only a disposable, unregistered copy created by prepare().
  func discardPrepared(path: String) throws {
    try checkRoot()
    let database = URL(fileURLWithPath: path).standardizedFileURL
    let folder = database.deletingLastPathComponent()
    guard database.lastPathComponent == "ledger.sqlite",
          folder.deletingLastPathComponent().path == root.path,
          UUID(uuidString: folder.lastPathComponent) != nil,
          folder.resolvingSymlinksInPath().standardizedFileURL.path == folder.path else { throw failure() }
    let folderInfo = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard folderInfo.isDirectory == true, folderInfo.isSymbolicLink != true else { throw failure() }
    let allowed: Set<String> = [pendingName, "ledger.sqlite", "ledger.sqlite-wal", "ledger.sqlite-shm", "ledger.sqlite-journal"]
    let contents = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard contents.contains(where: { $0.lastPathComponent == pendingName }) else { throw failure() }
    for item in contents {
      guard allowed.contains(item.lastPathComponent) else { throw failure() }
      let info = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard info.isRegularFile == true, info.isSymbolicLink != true else { throw failure() }
    }
    guard try Data(contentsOf: folder.appendingPathComponent(pendingName)) == pendingData else { throw failure() }
    try manager.removeItem(at: folder)
    guard !manager.fileExists(atPath: folder.path) else { throw failure() }
  }
  private func managedDatabase(_ path: String) throws -> URL {
    try checkRoot()
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let folder = url.deletingLastPathComponent()
    guard url.lastPathComponent == "ledger.sqlite",
          folder.deletingLastPathComponent().path == root.path,
          UUID(uuidString: folder.lastPathComponent) != nil,
          url.resolvingSymlinksInPath().standardizedFileURL.path == url.path,
          try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw failure() }
    return url
  }
  private func business(at url: URL) throws -> String {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let database { sqlite3_close(database) }; throw failure()
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "SELECT business_id FROM local_workspace WHERE singleton=1", -1, &statement, nil) == SQLITE_OK else { throw failure() }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { throw failure() }
    let id = String(cString: value)
    guard UUID(uuidString: id) != nil, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    return id
  }
  private func read(_ marker: URL) throws -> Entry {
    let info = try marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard info.isRegularFile == true, info.isSymbolicLink != true,
          (info.fileSize ?? 0) <= 16_384 else { throw failure() }
    let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: marker))
    guard (entry.version == 1 || entry.version == 2),
          (entry.baselineAuditSequence == nil
            ? entry.version == 1 && entry.markerExpired == nil
            : entry.baselineAuditSequence! >= 0),
          entry.id == marker.deletingLastPathComponent().lastPathComponent,
          UUID(uuidString: entry.id) != nil, UUID(uuidString: entry.businessId) != nil,
          !entry.name.isEmpty, entry.name.count <= 200,
          ISO8601DateFormatter().date(from: entry.createdAt) != nil else { throw failure() }
    return entry
  }
  private func auditNumber(at url: URL, sql: String) throws -> Int64 {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let database { sqlite3_close(database) }; throw failure()
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
    let value = sqlite3_column_int64(statement, 0)
    guard value >= 0, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    return value
  }
  private func baseline(at database: URL, businessId: String) throws -> Int64 {
    guard UUID(uuidString: businessId) != nil else { throw failure() }
    return try auditNumber(at: database,
      sql: "SELECT COALESCE(MAX(sequence),0) FROM ledger_audit WHERE business_id='\(businessId)'")
  }
  private func transactionCount(_ entry: Entry, at database: URL) throws -> Int {
    if entry.markerExpired == true { return 5 }
    guard let after = entry.baselineAuditSequence,
          UUID(uuidString: entry.businessId) != nil else { throw failure() }
    // The family and subject form one durable root, even if an event is retried.
    let count = try auditNumber(at: database, sql:
      "SELECT COUNT(*) FROM (SELECT 1 FROM ledger_audit WHERE business_id='\(entry.businessId)' AND sequence>\(after) AND kind='transaction_root_created' GROUP BY detail,subject_id LIMIT 5)")
    return Int(count)
  }
  private func write(_ entry: Entry, at database: URL) throws {
    let marker = database.deletingLastPathComponent().appendingPathComponent("workspace.json")
    let encoded = try JSONEncoder().encode(entry)
    guard encoded.count <= 16_384 else { throw failure() }
    try encoded.write(to: marker, options: .atomic)
    guard try read(marker) == entry else { throw failure() }
  }
  private func compatible(_ entry: Entry, at database: URL) throws -> Entry {
    if entry.baselineAuditSequence != nil { return entry }
    // Keep version 1: the previous installed reader ignores these new fields.
    let updated = Entry(version: 1, id: entry.id, businessId: entry.businessId,
                        name: entry.name, createdAt: entry.createdAt,
                        baselineAuditSequence: try baseline(at: database, businessId: entry.businessId),
                        markerExpired: false)
    try write(updated, at: database)
    return updated
  }
  private func observed(_ entry: Entry, at database: URL) throws -> (Entry, Int) {
    let current = try compatible(entry, at: database)
    let count = try transactionCount(current, at: database)
    guard count == 5, current.markerExpired != true else { return (current, count) }
    let expired = Entry(version: 1, id: current.id, businessId: current.businessId,
                        name: current.name, createdAt: current.createdAt,
                        baselineAuditSequence: current.baselineAuditSequence,
                        markerExpired: true)
    try write(expired, at: database)
    return (expired, 5)
  }
  private func result(_ entry: Entry, _ database: URL, available: Bool, transactionCount: Int) -> [String: Any] {
    ["id": entry.id, "businessId": entry.businessId, "name": entry.name,
     "createdAt": entry.createdAt, "path": database.path, "available": available,
     "newTransactionCount": transactionCount]
  }
  func register(path: String, businessId: String, name: String) throws -> [String: Any] {
    let database = try managedDatabase(path)
    guard UUID(uuidString: businessId) != nil, try business(at: database) == businessId,
          name.count <= 4000 else { throw failure() }
    let folder = database.deletingLastPathComponent()
    let marker = folder.appendingPathComponent("workspace.json")
    let pending = folder.appendingPathComponent(pendingName)
    let hasPending = try manager.contentsOfDirectory(atPath: folder.path).contains(pendingName)
    if hasPending {
      let info = try pending.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard info.isRegularFile == true, info.isSymbolicLink != true,
            try Data(contentsOf: pending) == pendingData else { throw failure() }
    }
    var createdAt = ISO8601DateFormatter().string(from: Date())
    var firstSequence = try baseline(at: database, businessId: businessId)
    var markerExpired = false
    if manager.fileExists(atPath: marker.path) {
      let old = try read(marker)
      guard old.businessId == businessId else { throw failure() }
      createdAt = old.createdAt
      firstSequence = old.baselineAuditSequence ?? firstSequence
      markerExpired = old.markerExpired == true
    }
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let entry = Entry(version: 1, id: folder.lastPathComponent, businessId: businessId,
                      name: cleanName.isEmpty ? "Restored Company" : String(cleanName.prefix(200)),
                      createdAt: createdAt, baselineAuditSequence: firstSequence,
                      markerExpired: markerExpired)
    try write(entry, at: database)
    if hasPending {
      try manager.removeItem(at: pending)
    }
    let (current, count) = try observed(entry, at: database)
    return result(current, database, available: true, transactionCount: count)
  }
  func lookup(path: String) throws -> [String: Any] {
    let database = try managedDatabase(path)
    let entry = try read(database.deletingLastPathComponent().appendingPathComponent("workspace.json"))
    guard try business(at: database) == entry.businessId else { throw failure() }
    let (current, count) = try observed(entry, at: database)
    return result(current, database, available: true, transactionCount: count)
  }
  func list() throws -> [String: Any] {
    if !manager.fileExists(atPath: root.path) { return ["workspaces": [], "issues": 0] }
    try checkRoot()
    var entries = [[String: Any]](), issues = 0
    for folder in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
      guard UUID(uuidString: folder.lastPathComponent) != nil else { continue }
      let marker = folder.appendingPathComponent("workspace.json")
      // An unfinished/failed import is not advertised as a completed recovery.
      guard manager.fileExists(atPath: marker.path) else { continue }
      do {
        guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw failure() }
        let entry = try read(marker)
        let database = folder.appendingPathComponent("ledger.sqlite").standardizedFileURL
        let available = (try? managedDatabase(database.path)).flatMap { try? business(at: $0) } == entry.businessId
        let (current, count) = available
          ? try observed(entry, at: database)
          : (entry, entry.markerExpired == true ? 5 : 0)
        entries.append(result(current, database, available: available,
                              transactionCount: count))
      } catch { issues += 1 }
    }
    entries.sort {
      let lhs = ($0["createdAt"] as! String, $0["id"] as! String)
      let rhs = ($1["createdAt"] as! String, $1["id"] as! String)
      return lhs > rhs
    }
    return ["workspaces": entries, "issues": issues]
  }
}

extension RestoredWorkspaceRegistry.Entry: Equatable {}
