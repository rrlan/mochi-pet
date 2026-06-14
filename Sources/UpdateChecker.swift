//
//  UpdateChecker.swift
//  Mochi
//
//  A lightweight "is there a newer release?" check against the GitHub Releases
//  API. It never installs anything — it just lets the app point the user at the
//  download page when a newer version is out.
//

import Foundation

enum UpdateChecker {
    struct Release {
        let version: String   // e.g. "0.1.2"
        let url: String       // the release page to open
    }

    static let repo = "rrlan/mochi-pet"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Fetch the latest release; call back on the main queue with it only when
    /// it's newer than the running build (nil if up to date or the check fails).
    static func checkLatest(completion: @escaping (Release?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.setValue("Mochi-pet", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let release = parse(data)
            DispatchQueue.main.async { completion(release) }
        }.resume()
    }

    private static func parse(_ data: Data?) -> Release? {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(latest, than: currentVersion) else { return nil }
        let page = (json["html_url"] as? String)
            ?? "https://github.com/\(repo)/releases/latest"
        return Release(version: latest, url: page)
    }

    /// Numeric, dot-separated compare: "0.1.2" > "0.1.10" is false, etc.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
