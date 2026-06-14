//
//  AIService.swift
//  Mochi
//
//  Bridges the pet to AI coding CLIs (Claude Code / Codex). Runs the chosen CLI
//  non-interactively through a *login* shell so the user's normal PATH (and
//  node, for the `claude` CLI) is available even when launched from a .app
//  bundle. The user's message is passed as a positional shell parameter ($1),
//  never interpolated into the script text — so quoting/injection is a non-issue.
//

import Foundation

enum AIEngine: String, CaseIterable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Command executed inside `zsh -lc`. `$1` is the (already-wrapped) prompt.
    var invocation: String {
        switch self {
        case .claude: return #"exec claude -p "$1""#
        case .codex:  return #"exec codex exec --skip-git-repo-check "$1""#
        }
    }
}

enum AIError: Error {
    case launchFailed
    case notInstalled(AIEngine)
    case timedOut
    case failed(String)
}

struct AIService {
    var engine: AIEngine
    var timeout: TimeInterval = 120

    /// Ask the AI a question off the main thread; the completion is always
    /// delivered back on the main thread.
    func ask(_ userText: String, completion: @escaping (Result<String, AIError>) -> Void) {
        let prompt = """
        你是用户 macOS 桌面上一只叫 Mochi 的可爱小宠物。请用中文、1 到 2 句话、\
        简短俏皮地回应用户，可以用一点 emoji。不要用列表，不要长篇大论，不要解释你是 AI。\
        用户说：\(userText)
        """
        let engine = self.engine
        let timeout = self.timeout

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", engine.invocation, "mochi", prompt]

            let outPipe = Pipe(), errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(.failure(.launchFailed)) }
                return
            }

            // Watchdog: terminate if the CLI hangs.
            var didTimeOut = false
            let watchdog = DispatchWorkItem {
                if process.isRunning { didTimeOut = true; process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

            // Drain both pipes concurrently to avoid a full-buffer deadlock.
            var outData = Data(), errData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave()
            }
            process.waitUntilExit()
            group.wait()
            watchdog.cancel()

            let out = (String(data: outData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let err = (String(data: errData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                if didTimeOut {
                    completion(.failure(.timedOut))
                } else if !out.isEmpty {
                    completion(.success(out))
                } else if err.lowercased().contains("command not found") {
                    completion(.failure(.notInstalled(engine)))
                } else {
                    completion(.failure(.failed(err.isEmpty ? "no output" : err)))
                }
            }
        }
    }
}
