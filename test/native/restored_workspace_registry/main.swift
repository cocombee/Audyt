import Foundation
import SQLite3

var assertions = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  guard try condition() else { fatalError(message) }
  assertions += 1
}
func rejected(_ message: String, _ action: () throws -> Void) throws {
  do { try action() } catch { assertions += 1; return }
  fatalError("Not rejected: \(message)")
}
let manager = FileManager.default
let temporary = manager.temporaryDirectory.resolvingSymlinksInPath()
  .appendingPathComponent("Audyt Restored Workspace Tests-" + UUID().uuidString, isDirectory: true)
try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: temporary) }
let root = temporary.appendingPathComponent("Restored Workspaces", isDirectory: true)
let registry = RestoredWorkspaceRegistry(root: root)
try check((try registry.list())["issues"] as? Int == 0, "New catalogue")
try check(!manager.fileExists(atPath: root.path), "Listing must not create a root")
func writeDatabase(_ url: URL, business: String) throws {
  var db: OpaquePointer?
  guard sqlite3_open(url.path, &db) == SQLITE_OK else { fatalError("Test database") }
  defer { sqlite3_close(db) }
  guard sqlite3_exec(db, "CREATE TABLE local_workspace(singleton INTEGER PRIMARY KEY,business_id TEXT); INSERT INTO local_workspace VALUES(1,'\(business)');", nil, nil, nil) == SQLITE_OK else { fatalError("Test schema") }
}
let database = try registry.prepare()
let business = UUID().uuidString.lowercased()
try writeDatabase(database, business: business)
try check(((try registry.list())["workspaces"] as? [[String: Any]])?.isEmpty == true, "Unfinished import hidden")
let originalBytes = try Data(contentsOf: database)
let saved = try registry.register(path: database.path, businessId: business, name: "Restored Sample Company")
try check(saved["available"] as? Bool == true, "Registered copy available")
try check(!manager.fileExists(atPath: database.deletingLastPathComponent().appendingPathComponent(".audyt-restore-pending").path), "Registration consumes pending marker")
try rejected("registered copy cannot be discarded") { try registry.discardPrepared(path: database.path) }
try check(try Data(contentsOf: database) == originalBytes, "Registered data survives rejected cleanup")
let cancelled = try registry.prepare()
try check(manager.fileExists(atPath: cancelled.deletingLastPathComponent().appendingPathComponent(".audyt-restore-pending").path), "Prepared copy has marker")
try registry.discardPrepared(path: cancelled.path)
try check(!manager.fileExists(atPath: cancelled.deletingLastPathComponent().path), "Empty prepared copy removed")
let failedRestore = try registry.prepare()
try writeDatabase(failedRestore, business: business)
try registry.discardPrepared(path: failedRestore.path)
try check(!manager.fileExists(atPath: failedRestore.deletingLastPathComponent().path), "Failed restored database removed")
let unexpected = try registry.prepare()
let extra = unexpected.deletingLastPathComponent().appendingPathComponent("user-file.txt")
try Data("keep".utf8).write(to: extra)
try rejected("unexpected file prevents cleanup") { try registry.discardPrepared(path: unexpected.path) }
try check(try Data(contentsOf: extra) == Data("keep".utf8), "Unexpected file untouched")
try manager.removeItem(at: extra)
try registry.discardPrepared(path: unexpected.path)
let linkedSidecar = try registry.prepare()
let outsideSidecar = temporary.appendingPathComponent("outside-sidecar")
try Data("keep".utf8).write(to: outsideSidecar)
let sidecar = linkedSidecar.deletingLastPathComponent().appendingPathComponent("ledger.sqlite-wal")
try manager.createSymbolicLink(at: sidecar, withDestinationURL: outsideSidecar)
try rejected("sidecar symlink prevents cleanup") { try registry.discardPrepared(path: linkedSidecar.path) }
try check(try Data(contentsOf: outsideSidecar) == Data("keep".utf8), "Symlink target untouched")
try manager.removeItem(at: sidecar)
try registry.discardPrepared(path: linkedSidecar.path)
let restarted = RestoredWorkspaceRegistry(root: root)
let entries = try restarted.list()["workspaces"] as! [[String: Any]]
try check(entries.count == 1 && entries[0]["path"] as? String == database.path, "Catalogue survives restart")
try check(try restarted.lookup(path: database.path)["businessId"] as? String == business, "Original company ID preserved")
try check(try Data(contentsOf: database) == originalBytes, "Registry read did not change SQLite bytes")
let updated = try restarted.register(path: database.path, businessId: business, name: "Renamed Sample")
try check(updated["createdAt"] as? String == saved["createdAt"] as? String, "Registration retry retains creation")
let longName = try registry.register(path: database.path, businessId: business, name: String(repeating: "A", count: 4000))
try check((longName["name"] as? String)?.count == 200, "Long saved business name uses bounded menu label")
_ = try registry.register(path: database.path, businessId: business, name: "Renamed Sample")
try rejected("mismatched company") { _ = try registry.register(path: database.path, businessId: UUID().uuidString, name: "Wrong") }
let outside = temporary.appendingPathComponent("original.sqlite")
try writeDatabase(outside, business: business)
let outsideBytes = try Data(contentsOf: outside)
try rejected("outside database") { _ = try registry.register(path: outside.path, businessId: business, name: "Original") }
try rejected("outside cleanup") { try registry.discardPrepared(path: outside.path) }
try check(try Data(contentsOf: outside) == outsideBytes, "Original outside database unchanged")
let marker = database.deletingLastPathComponent().appendingPathComponent("workspace.json")
let markerBytes = try Data(contentsOf: marker)
try manager.removeItem(at: database)
try check((try registry.list()["workspaces"] as! [[String: Any]])[0]["available"] as? Bool == false, "Missing database remains visibly unavailable")
try rejected("missing database") { _ = try registry.lookup(path: database.path) }
try check(!manager.fileExists(atPath: database.path), "Missing database not recreated")
try manager.createSymbolicLink(at: database, withDestinationURL: outside)
try rejected("database symlink") { _ = try registry.lookup(path: database.path) }
try manager.removeItem(at: database)
try writeDatabase(database, business: UUID().uuidString.lowercased())
try rejected("replaced company") { _ = try registry.lookup(path: database.path) }
try manager.removeItem(at: database)
try originalBytes.write(to: database)
try manager.removeItem(at: marker)
let outsideMarker = temporary.appendingPathComponent("outside.json")
try markerBytes.write(to: outsideMarker)
try manager.createSymbolicLink(at: marker, withDestinationURL: outsideMarker)
try rejected("marker symlink") { _ = try registry.lookup(path: database.path) }
try rejected("registration cannot replace marker symlink") { _ = try registry.register(path: database.path, businessId: business, name: "Wrong") }
try check(try Data(contentsOf: outsideMarker) == markerBytes, "Outside marker unchanged")
try check(try registry.list()["issues"] as? Int == 1, "Invalid copy reported")
try manager.removeItem(at: marker)
try Data("{broken}".utf8).write(to: marker)
try check(try registry.list()["issues"] as? Int == 1, "Corrupt marker reported")
try markerBytes.write(to: marker)
let linkedFolder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
try manager.createSymbolicLink(at: linkedFolder, withDestinationURL: database.deletingLastPathComponent())
try check(try registry.list()["issues"] as? Int == 1, "Folder symlink reported")
try manager.removeItem(at: linkedFolder)
let linkRoot = temporary.appendingPathComponent("Linked Root", isDirectory: true)
let target = temporary.appendingPathComponent("External Root", isDirectory: true)
try manager.createDirectory(at: target, withIntermediateDirectories: false)
try manager.createSymbolicLink(at: linkRoot, withDestinationURL: target)
try rejected("root symlink") { _ = try RestoredWorkspaceRegistry(root: linkRoot).prepare() }
try check(try manager.contentsOfDirectory(atPath: target.path).isEmpty, "No writes through root symlink")
try check(try registry.lookup(path: database.path)["name"] as? String == "Renamed Sample", "Valid copy still recoverable after failures")
print("Restored workspace registry: \(assertions) assertions passed")
