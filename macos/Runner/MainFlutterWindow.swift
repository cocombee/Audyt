import Cocoa
import FlutterMacOS
import PDFKit
import Security

class MainFlutterWindow: NSWindow {
  private var namingFolderURLs: [String: URL] = [:]
  private var namingFolderSelection = NamingFolderSelection()
  private var frameObservers: [NSObjectProtocol] = []
  private var popoutWidthOwners: [String: Double] = [:]
  private var popoutBaseMinimumWidth: CGFloat?

  private func growWindow(to requestedWidth: Double) -> Double {
    let width = max(frame.width, requestedWidth)
    let visible = (screen ?? NSScreen.main)?.visibleFrame
    var originX = frame.minX
    if let visible, originX + width > visible.maxX {
      originX = max(visible.minX, visible.maxX - width)
    }
    setFrame(NSRect(x: originX, y: frame.minY, width: width, height: frame.height),
             display: true)
    rememberFrame()
    return width
  }

  private func rememberFrame() {
    guard !styleMask.contains(.fullScreen) else { return }
    UserDefaults.standard.set(
      [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
      forKey: "audyt.window.frame")
  }

  deinit {
    for observer in frameObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func storedNamingFolder(_ kind: String) throws -> URL? {
    if let selected = namingFolderURLs[kind] { return selected }
    guard let bookmark = UserDefaults.standard.data(forKey: "audyt.setup.\(kind).folder") ?? (kind == "expense" ? UserDefaults.standard.data(forKey: "audyt.namingFolderBookmark") : nil) else { return nil }
    var stale = false
    let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    let canonical = url.resolvingSymlinksInPath().standardizedFileURL
    namingFolderURLs[kind] = canonical
    return canonical
  }

  private func finishFolderRelocations() throws {
    try ReceiptFolderRelocationRecovery.finishPending(defaults: UserDefaults.standard) {
      self.namingFolderURLs.removeAll()
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Let the accounting shell own the full window bounds. The native traffic
    // lights remain over the shell rather than sitting in a separate grey bar.
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    styleMask.insert(.fullSizeContentView)
    minSize = NSSize(width: 720, height: minSize.height)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    let windowLayout = FlutterMethodChannel(name: "audyt/window-layout",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowLayout.setMethodCallHandler { call, result in
      switch call.method {
      case "loadSidebarWidth":
        result(UserDefaults.standard.object(forKey: "audyt.sidebar.width") as? Double)
      case "saveSidebarWidth":
        guard let args = call.arguments as? [String: Any],
              let width = args["width"] as? Double else {
          result(FlutterError(code: "invalid_width", message: "Missing sidebar width", details: nil)); return
        }
        UserDefaults.standard.set(width, forKey: "audyt.sidebar.width")
        result(nil)
      case "growToWidth":
        guard let args = call.arguments as? [String: Any],
              let requestedWidth = args["width"] as? Double else {
          result(FlutterError(code: "invalid_width", message: "Missing window width", details: nil)); return
        }
        result(self.growWindow(to: requestedWidth))
      case "acquirePopoutWidth":
        guard let args = call.arguments as? [String: Any],
              let owner = args["owner"] as? String, !owner.isEmpty,
              let width = args["width"] as? Double, width.isFinite, width > 0 else {
          result(FlutterError(code: "invalid_width", message: "Missing popout width owner", details: nil)); return
        }
        if self.popoutWidthOwners.isEmpty {
          self.popoutBaseMinimumWidth = self.minSize.width
        }
        self.popoutWidthOwners[owner] = width
        let minimumWidth = max(Double(self.popoutBaseMinimumWidth ?? 720),
                               self.popoutWidthOwners.values.max() ?? 720)
        self.minSize = NSSize(width: minimumWidth, height: self.minSize.height)
        result(self.growWindow(to: minimumWidth))
      case "releasePopoutWidth":
        guard let args = call.arguments as? [String: Any],
              let owner = args["owner"] as? String else {
          result(FlutterError(code: "invalid_owner", message: "Missing popout width owner", details: nil)); return
        }
        self.popoutWidthOwners.removeValue(forKey: owner)
        let minimumWidth = max(Double(self.popoutBaseMinimumWidth ?? self.minSize.width),
                               self.popoutWidthOwners.values.max() ?? 0)
        self.minSize = NSSize(width: minimumWidth, height: self.minSize.height)
        if self.popoutWidthOwners.isEmpty { self.popoutBaseMinimumWidth = nil }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let authSession = FlutterMethodChannel(name: "audyt/auth-session",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    authSession.setMethodCallHandler { call, result in
      let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.cocombees.audyt.authentication",
        kSecAttrAccount as String: "current-session"]
      switch call.method {
      case "load":
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { result([String: String]()); return }
        guard status == errSecSuccess, let data = item as? Data,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
          result(FlutterError(code: "credentials_unavailable", message: "Session credentials could not be read.", details: nil)); return
        }
        result(value)
      case "save":
        guard let value = call.arguments as? [String: String],
              let origin = value["origin"], let url = URL(string: origin), url.scheme == "https", url.host != nil,
              let token = value["token"], token.range(of: "^audyt_[a-f0-9]{64}$", options: .regularExpression) != nil,
              let data = try? JSONSerialization.data(withJSONObject: ["origin": origin, "token": token]) else {
          result(FlutterError(code: "invalid_credentials", message: "Invalid session credentials.", details: nil)); return
        }
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        var status = update
        if update == errSecItemNotFound {
          var add = query
          add[kSecValueData as String] = data
          add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
          status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
          result(FlutterError(code: "credentials_unavailable", message: "Session credentials could not be saved.", details: nil)); return
        }
        result(nil)
      case "manageGooglePassword":
        NSWorkspace.shared.open(URL(string: "https://myaccount.google.com/security")!)
        result(nil)
      case "clear":
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
          result(FlutterError(code: "credentials_unavailable", message: "Session credentials could not be removed.", details: nil)); return
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    let localProfile = FlutterMethodChannel(name: "audyt/local-profile",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    localProfile.setMethodCallHandler { call, result in
      switch call.method {
      case "load":
        let args = call.arguments as? [String: String] ?? [:]
        let subject = args["googleSubject"] ?? ""
        if !subject.isEmpty {
          result(UserDefaults.standard.dictionary(forKey: "audyt.profiles.google." + subject) as? [String: String] ?? [:])
        } else {
          let fields = ["name", "email", "phone", "jobTitle", "role", "photo", "department", "employeeReference", "responsibility"]
          result(Dictionary(uniqueKeysWithValues: fields.map {
            ($0, UserDefaults.standard.string(forKey: "audyt.profile." + $0) ?? "")
          }))
        }
      case "list":
        let profiles = UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> [String: String]? in
          guard key.hasPrefix("audyt.profiles.google."), let profile = value as? [String: String],
                let email = profile["email"], !email.isEmpty else { return nil }
          return ["email": email, "loginEmail": profile["loginEmail"] ?? email, "name": profile["name"] ?? "", "googleSubject": profile["googleSubject"] ?? ""]
        }
        result(profiles.sorted { ($0["email"] ?? "") < ($1["email"] ?? "") })
      case "save":
        guard let args = call.arguments as? [String: String],
              let name = args["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
          result(FlutterError(code: "invalid_profile", message: "Enter your name.", details: nil)); return
        }
        guard let role = args["role"], ["Director", "Accountant"].contains(role) else {
          result(FlutterError(code: "invalid_profile", message: "Choose Director or Accountant.", details: nil)); return
        }
        let photo = args["photo"] ?? ""
        guard photo.isEmpty || (photo.count < 1_000_000 && Data(base64Encoded: photo) != nil) else {
          result(FlutterError(code: "invalid_profile", message: "Choose a smaller profile photo.", details: nil)); return
        }
        let fields = ["name", "email", "phone", "jobTitle", "role", "photo", "department", "employeeReference", "responsibility", "googleSubject", "loginEmail"]
        let values = Dictionary(uniqueKeysWithValues: fields.map {
          ($0, args[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        })
        let subject = values["googleSubject"] ?? ""
        if subject.isEmpty {
          for (field, value) in values {
            UserDefaults.standard.set(value, forKey: "audyt.profile." + field)
          }
        } else {
          UserDefaults.standard.set(values, forKey: "audyt.profiles.google." + subject)
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    // NSWindow's legacy autosave also restores macOS tiling state, which can
    // force the old half-screen frame after our preferred size is applied.
    // Keep only Audyt's explicit frame value for subsequent user resizes.
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "NSWindow Frame Audyt Main Window")
    let saved = defaults.array(forKey: "audyt.window.frame") as? [Double]
    let preferredFrameKey = "audyt.window.preferredDefault.1162x809.v2"
    let oldDefault = saved.map { frame in
      frame.count == 4 && (
        (abs(frame[2] - 1224) < 1 && abs(frame[3] - 1000) < 1) ||
        (abs(frame[2] - 1028) < 1 && abs(frame[3] - 612) < 1))
    } ?? false
    let useSaved = saved?.count == 4 &&
      (defaults.bool(forKey: preferredFrameKey) || !oldDefault)
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      if useSaved, let saved {
        let width = min(max(720, saved[2]), visible.width)
        let height = min(max(minSize.height, saved[3]), visible.height)
        let x = min(max(saved[0], visible.minX), max(visible.minX, visible.maxX - width))
        let y = min(max(saved[1], visible.minY), max(visible.minY, visible.maxY - height))
        self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
      } else {
        let size = NSSize(width: min(1162, visible.width), height: min(809, visible.height))
        self.setFrame(NSRect(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2,
                             width: size.width, height: size.height), display: true)
      }
    }
    defaults.set(true, forKey: preferredFrameKey)
    rememberFrame()
    for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
      frameObservers.append(NotificationCenter.default.addObserver(
        forName: name, object: self, queue: .main) { [weak self] _ in
          self?.rememberFrame()
        })
    }
    let documentPreview = FlutterMethodChannel(name: "audyt/document-preview",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    documentPreview.setMethodCallHandler { call, result in
      guard call.method == "pdfPage",
            let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData,
            let index = args["page"] as? Int else {
        result(FlutterError(code: "preview_unavailable", message: "The PDF is invalid, locked, or this page is unavailable.", details: nil)); return
      }
      do {
        let preview = try DocumentPreviewRenderer.render(bytes.data, page: index)
        result(["bytes": FlutterStandardTypedData(bytes: preview.bytes), "pages": preview.pages])
      } catch {
        result(FlutterError(code: "preview_unavailable", message: error.localizedDescription, details: nil))
      }
    }
    let statementText = FlutterMethodChannel(name: "audyt/statement-text",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    statementText.setMethodCallHandler { call, result in
      guard call.method == "positionedGlyphs",
            let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData,
            let document = PDFDocument(data: bytes.data), !document.isLocked,
            document.pageCount > 0 else {
        result(FlutterError(code: "statement_unreadable", message: "The PDF cannot be read.", details: nil)); return
      }
      var pages = Array(repeating: [[Any]](), count: document.pageCount)
      guard let selections = document.selectionForEntireDocument?.selectionsByLine() else {
        result(FlutterError(code: "statement_unreadable", message: "The PDF has no selectable statement text.", details: nil)); return
      }
      for selection in selections {
        guard let page = selection.pages.first,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { continue }
        let index = document.index(for: page)
        guard index >= 0 && index < pages.count else { continue }
        let bounds = selection.bounds(for: page)
        if bounds.width <= 0 || !bounds.origin.x.isFinite || !bounds.origin.y.isFinite { continue }
        pages[index].append([
          Int((bounds.minX * 10).rounded()),
          Int((bounds.midY * 10).rounded()),
          Int((bounds.width * 10).rounded()),
          text,
        ])
      }
      result(pages)
    }
    let backup = FlutterMethodChannel(name: "audyt/workspace-backup",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    backup.setMethodCallHandler { [weak self] call, result in
      guard let self = self, let args = call.arguments as? [String: Any],
            let businessId = args["businessId"] as? String, UUID(uuidString: businessId) != nil else {
        result(FlutterError(code: "backup_identity", message: "A valid company identity is required.", details: nil)); return
      }
      let workspaceId = args["workspaceId"] as? String
      if args["workspaceId"] != nil && (workspaceId == nil || UUID(uuidString: workspaceId!) == nil) {
        result(FlutterError(code: "backup_identity", message: "A valid workspace identity is required.", details: nil)); return
      }
      // A recovered copy must not inherit the original's destination/timestamp.
      let key = workspaceId.map { "audyt.backup.copy.\($0)" } ?? "audyt.backup.\(businessId)"
      do {
        switch call.method {
        case "info":
          var info: [String: Any] = [:]
          if let bookmark = UserDefaults.standard.data(forKey: key + ".folder") {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            info["folder"] = folder.path
          }
          info["lastSuccess"] = UserDefaults.standard.string(forKey: key + ".lastSuccess")
          info["lastFailure"] = UserDefaults.standard.string(forKey: key + ".lastFailure")
          result(info)
        case "recordFailure":
          UserDefaults.standard.set(args["message"] as? String, forKey: key + ".lastFailure")
          result(nil)
        case "chooseFolder":
          let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
          panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
          panel.beginSheetModal(for: self) { response in
            guard response == .OK, let url = panel.url else { result(nil); return }
            do {
              let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
              UserDefaults.standard.set(bookmark, forKey: key + ".folder"); result(url.path)
            } catch { result(FlutterError(code: "backup_folder", message: error.localizedDescription, details: nil)) }
          }
        case "write", "export":
          guard let text = args["data"] as? String, let bytes = text.data(using: .utf8),
                let ext = args["extension"] as? String, ["audyt.json", "csv"].contains(ext) else {
            result(FlutterError(code: "backup_data", message: "Invalid export data.", details: nil)); return
          }
          if call.method == "export" {
            let panel = NSSavePanel(); panel.nameFieldStringValue = "Audyt Export." + ext
            panel.beginSheetModal(for: self) { response in
              guard response == .OK, let url = panel.url else { result(nil); return }
              do { try bytes.write(to: url, options: .atomic); guard try Data(contentsOf: url) == bytes else { throw NSError(domain: "Audyt", code: 1) }; result(url.path) }
              catch { result(FlutterError(code: "export_write", message: error.localizedDescription, details: nil)) }
            }
          } else {
            guard let bookmark = UserDefaults.standard.data(forKey: key + ".folder") else { throw NSError(domain: "Choose a backup folder first.", code: 1) }
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = folder.startAccessingSecurityScopedResource(); defer { if access { folder.stopAccessingSecurityScopedResource() } }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = folder.appendingPathComponent("Audyt-" + stamp + "-" + String(UUID().uuidString.prefix(8)) + "." + ext)
            try bytes.write(to: url, options: .atomic)
            guard try Data(contentsOf: url) == bytes else { throw NSError(domain: "Backup verification failed.", code: 1) }
            UserDefaults.standard.set(args["createdAt"], forKey: key + ".lastSuccess"); UserDefaults.standard.removeObject(forKey: key + ".lastFailure"); result(url.path)
          }
        case "import":
          let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
          panel.beginSheetModal(for: self) { response in
            guard response == .OK, let url = panel.url else { result(nil); return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
              guard size <= 500_000_000 else { throw NSError(domain: "The archive is too large.", code: 1) }
              result(["path": url.path, "data": try String(contentsOf: url, encoding: .utf8)])
            } catch { result(FlutterError(code: "backup_import", message: error.localizedDescription, details: nil)) }
          }
        case "newWorkspace":
          let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
          let registry = RestoredWorkspaceRegistry(root: support.resolvingSymlinksInPath().appendingPathComponent("Audyt/Restored Workspaces", isDirectory: true))
          result(try registry.prepare().path)
        case "discardPreparedWorkspace":
          guard let path = args["path"] as? String else {
            result(FlutterError(code: "backup_identity", message: "A prepared workspace path is required.", details: nil)); return
          }
          let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
          let registry = RestoredWorkspaceRegistry(root: support.resolvingSymlinksInPath().appendingPathComponent("Audyt/Restored Workspaces", isDirectory: true))
          try registry.discardPrepared(path: path)
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch { result(FlutterError(code: "workspace_backup", message: error.localizedDescription, details: nil)) }
    }
    let storage = FlutterMethodChannel(name: "audyt/local-storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    storage.setMethodCallHandler { call, result in
      do {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
          in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Audyt", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let registry = RestoredWorkspaceRegistry(root: directory.resolvingSymlinksInPath().appendingPathComponent("Restored Workspaces", isDirectory: true))
        switch call.method {
        case "databasePath": result(directory.appendingPathComponent("ledger.sqlite").path)
        case "listRestoredWorkspaces": result(try registry.list())
        case "registerRestoredWorkspace":
          guard let args = call.arguments as? [String: String], let path = args["path"],
                let businessId = args["businessId"], let name = args["name"] else {
            result(FlutterError(code: "restored_workspace", message: "Invalid restored workspace.", details: nil)); return
          }
          result(try registry.register(path: path, businessId: businessId, name: name))
        case "restoredWorkspace":
          guard let args = call.arguments as? [String: String], let path = args["path"] else {
            result(FlutterError(code: "restored_workspace", message: "Invalid restored workspace.", details: nil)); return
          }
          result(try registry.lookup(path: path))
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "local_storage", message: error.localizedDescription, details: nil))
      }
    }
    let settings = FlutterMethodChannel(name: "audyt/naming-settings",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    settings.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      let kind = args?["kind"] as? String ?? "expense"
      guard ["expense", "invoice", "voucher", "claims"].contains(kind) else {
        result(FlutterError(code: "invalid_setup", message: "Unknown setup type", details: nil)); return
      }
      switch call.method {
      case "prepareDemoSetups":
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Users/mrkokom/Downloads/Audyt Demo", isDirectory: true)
        panel.message = "Choose the Audyt Demo folder in Downloads to prepare missing transaction setups. Existing setups are preserved."
        panel.prompt = "Use Demo Folder"
        panel.beginSheetModal(for: self) { response in
          guard response == .OK, let root = panel.url else { result(nil); return }
          guard root.standardizedFileURL.path == "/Users/mrkokom/Downloads/Audyt Demo" else {
            result(FlutterError(code: "demo_root", message: "Choose Audyt Demo inside Downloads for this sample setup.", details: nil)); return
          }
          let access = root.startAccessingSecurityScopedResource()
          defer { if access { root.stopAccessingSecurityScopedResource() } }
          do {
            try self.finishFolderRelocations()
            for (kind, name) in [("expense", "Expenses"), ("invoice", "Invoices"), ("claims", "Claims"), ("voucher", "Payment Vouchers")] {
              let folder = root.appendingPathComponent(name, isDirectory: true)
              try FileManager.default.createDirectory(at: folder.appendingPathComponent("2026/09. September 2026", isDirectory: true), withIntermediateDirectories: true)
              let folderKey = "audyt.setup.\(kind).folder"
              if UserDefaults.standard.data(forKey: folderKey) == nil && !(kind == "expense" && UserDefaults.standard.data(forKey: "audyt.namingFolderBookmark") != nil) {
                let bookmark = try folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: folderKey)
                self.namingFolderURLs[kind] = folder
              }
              let formatKey = "audyt.setup.\(kind).format"
              if UserDefaults.standard.string(forKey: formatKey) == nil && !(kind == "expense" && UserDefaults.standard.string(forKey: "audyt.namingFormat") != nil) {
                let blocks = [["type":"custom", "text":"DEMO"], ["type":"separator", "text":"-"], ["type":"day", "text":""], ["type":"month", "text":""], ["type":"year", "text":""]]
                let data = try JSONSerialization.data(withJSONObject: blocks)
                UserDefaults.standard.set(String(data: data, encoding: .utf8), forKey: formatKey)
              }
            }
            result("Demo folders and missing setups are ready. Existing setups were preserved.")
          } catch { result(FlutterError(code: "demo_setup", message: error.localizedDescription, details: nil)) }
        }
      case "load":
        do {
          try self.finishFolderRelocations()
          result(UserDefaults.standard.string(forKey: "audyt.setup.\(kind).format") ?? (kind == "expense" ? UserDefaults.standard.string(forKey: "audyt.namingFormat") : nil))
        } catch { result(FlutterError(code: "folder_access", message: error.localizedDescription, details: nil)) }
      case "loadFolder":
        self.namingFolderSelection.discard(kind: kind)
        self.namingFolderURLs.removeValue(forKey: kind)
        do { try self.finishFolderRelocations(); result(try self.storedNamingFolder(kind)?.path) }
        catch { result(FlutterError(code: "folder_access", message: error.localizedDescription, details: nil)) }
      case "chooseFolder":
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.beginSheetModal(for: self) { response in
          guard response == .OK, let url = panel.url else { result(nil); return }
          let path = url.standardizedFileURL.path
          if path == "/Users/mrkokom/Documents" || path.hasPrefix("/Users/mrkokom/Documents/") {
            result(FlutterError(code: "excluded_folder", message: "Choose a Google Drive destination.", details: nil))
            return
          }
          self.namingFolderSelection.choose(kind: kind, url: url)
          result(url.path)
        }
      case "deployFolder":
        do {
          try self.finishFolderRelocations()
          guard let args = call.arguments as? [String: Any],
                let year = args["year"] as? Int, let month = args["month"] as? Int,
                (1900...9999).contains(year), (1...12).contains(month),
                let root = try self.storedNamingFolder(kind) else {
            result(FlutterError(code: "invalid_folder", message: "Choose a folder and valid date.", details: nil))
            return
          }
          let access = root.startAccessingSecurityScopedResource()
          defer { if access { root.stopAccessingSecurityScopedResource() } }
          let destination = root.appendingPathComponent(String(year), isDirectory: true)
            .appendingPathComponent(try ReceiptDestinationWriter.monthFolderName(year: year, month: month), isDirectory: true)
          let bookmark = try root.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
          try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
          UserDefaults.standard.set(bookmark, forKey: "audyt.setup.\(kind).folder")
          result(destination.path)
        } catch { result(FlutterError(code: "folder_creation", message: error.localizedDescription, details: nil)) }
      case "commitSetup":
        do {
          try self.finishFolderRelocations()
          guard let args, let format = args["format"] as? String,
                let folderPath = args["folderPath"] as? String,
                let year = args["year"] as? Int, let month = args["month"] as? Int,
                (1900...9999).contains(year), (1...12).contains(month),
                let blocks = try JSONSerialization.jsonObject(with: Data(format.utf8)) as? [[String: Any]], !blocks.isEmpty else {
            throw NSError(domain: "Complete a valid folder and naming format.", code: 1)
          }
          let root = try self.namingFolderSelection.rootForCommit(kind: kind, expectedPath: folderPath, savedRoot: self.storedNamingFolder(kind))
          let destination = try ReceiptFolderSetupCommit.commit(kind: kind, format: format,
            root: root, year: year, month: month, defaults: UserDefaults.standard) {
            self.namingFolderURLs.removeAll()
          }
          self.namingFolderSelection.discard(kind: kind)
          result(destination.path)
        } catch { result(FlutterError(code: "folder_relocation", message: error.localizedDescription, details: nil)) }
      case "saveDocument":
        do {
          try self.finishFolderRelocations()
          guard let args, let year = args["year"] as? Int, let month = args["month"] as? Int,
                let filename = args["filename"] as? String,
                let attachmentId = args["attachmentId"] as? String, !attachmentId.isEmpty,
                let bytes = args["bytes"] as? FlutterStandardTypedData,
                let root = try self.storedNamingFolder(kind),
                (UserDefaults.standard.string(forKey: "audyt.setup.\(kind).format") ?? (kind == "expense" ? UserDefaults.standard.string(forKey: "audyt.namingFormat") : nil)) != nil else {
            result(FlutterError(code: "setup_required", message: "Set up a destination folder and naming format before saving.", details: nil)); return
          }
          let access = root.startAccessingSecurityScopedResource()
          defer { if access { root.stopAccessingSecurityScopedResource() } }
          let destination = try ReceiptFiledDocumentStore.save(kind: kind, attachmentId: attachmentId,
            root: root, year: year, month: month, filename: filename, data: bytes.data, defaults: UserDefaults.standard,
            generated: args["generated"] as? Bool == true)
          result(destination.path)
        } catch { result(FlutterError(code: "document_save", message: error.localizedDescription, details: nil)) }
      case "readDocument":
        do {
          guard let attachmentId = args?["attachmentId"] as? String, !attachmentId.isEmpty,
                let expectedHash = args?["expectedSha256"] as? String,
                expectedHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw CocoaError(.fileReadCorruptFile) }
          let loaded = try ReceiptFiledDocumentStore.read(attachmentId: attachmentId, expectedHash: expectedHash,
            defaults: UserDefaults.standard) { self.namingFolderURLs.removeAll() }
          result(["bytes": FlutterStandardTypedData(bytes: loaded.bytes), "mimeType": loaded.mimeType])
        } catch { result(FlutterError(code: "document_unavailable", message: error.localizedDescription, details: nil)) }
      case "save":
        do { try self.finishFolderRelocations() }
        catch { result(FlutterError(code: "folder_access", message: error.localizedDescription, details: nil)); return }
        guard let value = args?["format"] as? String else {
          result(FlutterError(code: "invalid_format", message: "Expected format JSON", details: nil))
          return
        }
        UserDefaults.standard.set(value, forKey: "audyt.setup.\(kind).format")
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    // Keep the native traffic lights on the same left inset as the Overview
    // label in the accounting sidebar after AppKit finishes laying out the window.
    if let closeButton = standardWindowButton(.closeButton),
       let buttonGroup = closeButton.superview {
      var groupFrame = buttonGroup.frame
      groupFrame.origin.x = 9
      buttonGroup.setFrameOrigin(groupFrame.origin)
    }
  }
}
