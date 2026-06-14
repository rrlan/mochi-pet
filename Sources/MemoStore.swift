//
//  MemoStore.swift
//  Mochi
//
//  Appends quick memos to Apple Notes.
//

import AppKit
import Foundation

enum MemoStore {
    static let noteTitle = "Mochi Memos"

    private static var homeDir: URL {
        if let override = ProcessInfo.processInfo.environment["MOCHI_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mochi")
    }

    static var errorLogURL: URL {
        homeDir.appendingPathComponent("memo-errors.log")
    }

    static func append(_ text: String, date: Date = Date()) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let line = "\(formatter.string(from: date)) \(text)"

        let script = """
        tell application "Notes"
            if not (exists note "\(noteTitle.appleScriptEscaped)") then
                make new note with properties {name:"\(noteTitle.appleScriptEscaped)", body:"<h1>\(noteTitle.htmlEscaped.appleScriptEscaped)</h1>"}
            end if
            set targetNote to note "\(noteTitle.appleScriptEscaped)"
            set body of targetNote to (body of targetNote) & "<div>• \(line.htmlEscaped.appleScriptEscaped)</div>"
            activate
        end tell
        """

        do {
            try runAppleScript(script)
        } catch {
            log(error)
            throw error
        }
    }

    static func open() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
    }

    private static func runAppleScript(_ source: String) throws {
        guard let appleScript = NSAppleScript(source: source) else {
            throw MemoError.compileFailed("Unable to create AppleScript")
        }

        var errorInfo: NSDictionary?
        _ = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw MemoError.appleScriptFailed(errorInfo.description)
        }
    }

    private static func log(_ error: Error) {
        try? FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        let line = "\(Date()) \(error)\n"
        if FileManager.default.fileExists(atPath: errorLogURL.path),
           let handle = try? FileHandle(forWritingTo: errorLogURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: errorLogURL, atomically: true, encoding: .utf8)
        }
    }
}

enum MemoError: Error {
    case compileFailed(String)
    case launchFailed(String)
    case appleScriptFailed(String)
}

private extension String {
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
