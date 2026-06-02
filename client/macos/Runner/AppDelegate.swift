import Cocoa
import FlutterMacOS

final class DirectoryAccessPlugin: NSObject {
  private var activeSecurityScopedUrls: [String: URL] = [:]

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "content_seeker/directory_access",
      binaryMessenger: binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "DirectoryAccessPlugin unavailable", details: nil))
        return
      }
      switch call.method {
      case "pickDirectory":
        self.handlePickDirectory(result: result)
      case "resolveBookmark":
        self.handleResolveBookmark(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handlePickDirectory(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "选择此目录"
    panel.message = "选择一个供 Content Seeker 写入缓存/录制文件的目录"

    let response = panel.runModal()
    guard response == .OK, let url = panel.url else {
      result(nil)
      return
    }

    do {
      guard url.startAccessingSecurityScopedResource() else {
        result(FlutterError(code: "access_denied", message: "无法获取目录访问权限", details: url.path))
        return
      }
      activeSecurityScopedUrls[url.path] = url
      let bookmarkData = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var payload = directoryPayload(for: url)
      payload["path"] = url.path
      payload["bookmark"] = bookmarkData.base64EncodedString()
      result(payload)
    } catch {
      result(FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func handleResolveBookmark(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let bookmark = args["bookmark"] as? String,
      let data = Data(base64Encoded: bookmark)
    else {
      result(FlutterError(code: "bad_args", message: "缺少 bookmark 参数", details: nil))
      return
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if activeSecurityScopedUrls[url.path] == nil {
        guard url.startAccessingSecurityScopedResource() else {
          result(FlutterError(code: "access_denied", message: "无法恢复目录访问权限", details: url.path))
          return
        }
        activeSecurityScopedUrls[url.path] = url
      }
      var payload = directoryPayload(for: url)
      payload["path"] = url.path

      if isStale {
        let refreshed = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        payload["bookmark"] = refreshed.base64EncodedString()
      }

      result(payload)
    } catch {
      result(FlutterError(code: "resolve_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func directoryPayload(for url: URL) -> [String: Any] {
    var payload: [String: Any] = [
      "path": url.path,
      "hasAccess": true,
      "writable": false,
    ]

    do {
      try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
      )
      let probeURL = url.appendingPathComponent(
        ".seeker_scope_probe_\(UUID().uuidString)"
      )
      try Data("ok".utf8).write(to: probeURL, options: .atomic)
      try FileManager.default.removeItem(at: probeURL)
      payload["writable"] = true
    } catch {
      payload["error"] = error.localizedDescription
    }

    return payload
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
