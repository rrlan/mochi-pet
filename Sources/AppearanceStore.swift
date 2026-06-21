//
//  AppearanceStore.swift
//  Mochi
//
//  A small *library* of appearance packs the user can switch between.
//
//  Each pack is a folder under `~/.mochi/packs/<slug>/` holding the role images
//  (companion/work/rest/slack/drag.png) plus an optional `walk/` frame folder
//  and a `name.txt` display name. One pack is "active" at a time (remembered in
//  UserDefaults); an empty active slug means the built-in vector Mochi.
//
//  Switching is now just flipping the active slug — packs are kept side by side
//  instead of the old single slot that got clobbered on every import.
//

import AppKit

/// One installed appearance pack, surfaced to the picker.
struct AppearancePack: Identifiable {
    let slug: String          // folder name under packs/
    let name: String          // display name (name.txt, else slug)
    let dir: URL
    let thumbnail: NSImage?    // companion.png, or the first role found

    var id: String { slug }
}

enum AppearanceStore {
    private static let activeKey = "MochiActivePack"
    private static let seededKey = "MochiSeededPacks"
    private static let roamersKey = "MochiRoamerPacks"

    /// Most ambient ("roaming") cats allowed alongside the working cat.
    static let maxRoamers = 4

    private static var homeDir: URL {
        if let override = ProcessInfo.processInfo.environment["MOCHI_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mochi")
    }

    /// The library of switchable packs.
    static var packsDir: URL { homeDir.appendingPathComponent("packs", isDirectory: true) }

    // Legacy single-slot locations, kept only for one-time migration.
    private static var legacyAppearancesDir: URL { homeDir.appendingPathComponent("appearances", isDirectory: true) }
    private static var legacyImageURL: URL { homeDir.appendingPathComponent("appearance.png") }

    /// Slug of the active pack; "" means the built-in vector Mochi. This is the
    /// "working cat" — the only one that senses agents and shows status bubbles.
    static var activeSlug: String {
        get { UserDefaults.standard.string(forKey: activeKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: activeKey) }
    }

    /// Packs that also roam the screen as ambient companions (no agent role).
    static var roamerSlugs: [String] {
        get { UserDefaults.standard.stringArray(forKey: roamersKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: roamersKey) }
    }

    static func isRoamer(_ slug: String) -> Bool { roamerSlugs.contains(slug) }

    /// Flip a pack's roaming flag. Returns false if it would exceed `maxRoamers`
    /// (so the caller can ignore the tap rather than silently dropping it).
    @discardableResult
    static func toggleRoamer(_ slug: String) -> Bool {
        guard !slug.isEmpty else { return false }
        var set = roamerSlugs
        if let i = set.firstIndex(of: slug) {
            set.remove(at: i)
        } else {
            guard set.count < maxRoamers else { return false }
            set.append(slug)
        }
        roamerSlugs = set
        return true
    }

    // MARK: - One-time setup (called once on launch, before loading)

    /// Adopt anything dropped in the legacy single-slot folder, then copy in the
    /// example packs bundled with the app. Idempotent; safe to call every launch.
    static func prepareLibrary() {
        adoptLegacyDropFolder()
        adoptLegacySingleImage()
        seedBundledPacks()
    }

    /// The earliest format was a single `~/.mochi/appearance.png` (companion only).
    /// Fold it into a pack so those very-early users keep their look on upgrade.
    private static func adoptLegacySingleImage() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyImageURL.path) else { return }
        let slug = uniqueSlug(preferred: "my-pack")
        let dest = packsDir.appendingPathComponent(slug, isDirectory: true)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try fm.moveItem(at: legacyImageURL, to: dest.appendingPathComponent("companion.png"))
            try? "我的形象".write(to: dest.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
            activeSlug = slug
        } catch {
            try? fm.removeItem(at: dest)   // don't leave a half-made empty pack
        }
    }

    /// Fold the old `~/.mochi/appearances` into the library. This is both the
    /// one-time migration for existing users *and* the pickup path for the
    /// `generate_appearance_pack.py --install` tool, which still writes there —
    /// so it runs on every launch whenever that folder holds role images.
    private static func adoptLegacyDropFolder() {
        let fm = FileManager.default
        let hasRoleImages = ((try? fm.contentsOfDirectory(atPath: legacyAppearancesDir.path))?
            .contains { $0.lowercased().hasSuffix(".png") }) ?? false
        guard hasRoleImages else { return }

        let slug = uniqueSlug(preferred: "my-pack")
        let dest = packsDir.appendingPathComponent(slug, isDirectory: true)
        try? fm.createDirectory(at: packsDir, withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: legacyAppearancesDir, to: dest)
            try? "我的形象".write(to: dest.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
            activeSlug = slug
        } catch {
            // Leave the legacy folder in place if the move fails; not fatal.
        }
    }

    /// Copy example packs shipped inside the app bundle into the library. Each
    /// bundled pack is seeded at most once (tracked by slug), so deleting one
    /// won't make it reappear, and newly-shipped packs still show up on upgrade.
    private static func seedBundledPacks() {
        let fm = FileManager.default
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("packs", isDirectory: true),
              let entries = try? fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: [.isDirectoryKey])
        else { return }

        var seeded = Set(UserDefaults.standard.stringArray(forKey: seededKey) ?? [])
        for src in entries where isDirectory(src) {
            let slug = src.lastPathComponent
            guard !seeded.contains(slug) else { continue }
            let dest = packsDir.appendingPathComponent(slug, isDirectory: true)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.createDirectory(at: packsDir, withIntermediateDirectories: true)
                try? fm.copyItem(at: src, to: dest)
            }
            seeded.insert(slug)
        }
        UserDefaults.standard.set(Array(seeded), forKey: seededKey)
    }

    // MARK: - Reading

    /// Images + walk frames for the currently active pack ([:], [] for default).
    static func loadActive() -> (appearances: [AppearanceRole: NSImage], walk: [NSImage]) {
        let slug = activeSlug
        if !slug.isEmpty,
           !FileManager.default.fileExists(atPath: packsDir.appendingPathComponent(slug).path) {
            activeSlug = ""                       // active pack was deleted; fall back
            return ([:], [])
        }
        return load(slug: slug)
    }

    /// Images + walk frames for any pack by slug ([:], [] for "" / a missing pack).
    static func load(slug: String) -> (appearances: [AppearanceRole: NSImage], walk: [NSImage]) {
        guard !slug.isEmpty else { return ([:], []) }
        let dir = packsDir.appendingPathComponent(slug, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return ([:], []) }
        return (loadRoleImages(in: dir), loadWalkFrames(in: dir))
    }

    /// Every installed pack, sorted by display name.
    static func installedPacks() -> [AppearancePack] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: packsDir, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }
        return entries
            .filter(isDirectory)
            .map { dir -> AppearancePack in
                let slug = dir.lastPathComponent
                let named = (try? String(contentsOf: dir.appendingPathComponent("name.txt"), encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return AppearancePack(slug: slug,
                                      name: (named?.isEmpty == false) ? named! : slug,
                                      dir: dir,
                                      thumbnail: thumbnail(in: dir))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func loadRoleImages(in dir: URL) -> [AppearanceRole: NSImage] {
        var result: [AppearanceRole: NSImage] = [:]
        for role in AppearanceRole.allCases {
            if let image = NSImage(contentsOf: dir.appendingPathComponent("\(role.rawValue).png")) {
                result[role] = image
            }
        }
        return result
    }

    private static func loadWalkFrames(in dir: URL) -> [NSImage] {
        let walkDir = dir.appendingPathComponent("walk", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: walkDir, includingPropertiesForKeys: nil)
        else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { NSImage(contentsOf: $0) }
    }

    private static func thumbnail(in dir: URL) -> NSImage? {
        if let companion = NSImage(contentsOf: dir.appendingPathComponent("companion.png")) { return companion }
        for role in AppearanceRole.allCases {
            if let image = NSImage(contentsOf: dir.appendingPathComponent("\(role.rawValue).png")) { return image }
        }
        return nil
    }

    // MARK: - Writing

    /// Install a whole appearance-pack folder into the library (state images in
    /// its root, assigned to roles by filename, plus any `walk/` frames) and make
    /// it active. Unlike before, this *adds* a pack instead of replacing the slot.
    @discardableResult
    static func importPack(from folder: URL) throws -> AppearancePack {
        let fm = FileManager.default
        let assignments = assign(pngs(in: folder))
        let walkFrames = pngs(in: folder.appendingPathComponent("walk", isDirectory: true))
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !assignments.isEmpty || !walkFrames.isEmpty else { throw AppearanceError.unreadableImage }

        let slug = uniqueSlug(preferred: folder.deletingPathExtension().lastPathComponent)
        let dir = packsDir.appendingPathComponent(slug, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var wrote = 0
        for (role, src) in assignments {
            if (try? fm.copyItem(at: src, to: dir.appendingPathComponent("\(role.rawValue).png"))) != nil { wrote += 1 }
        }
        if !walkFrames.isEmpty {
            let walkDir = dir.appendingPathComponent("walk", isDirectory: true)
            try fm.createDirectory(at: walkDir, withIntermediateDirectories: true)
            for (i, src) in walkFrames.enumerated() {
                if (try? fm.copyItem(at: src, to: walkDir.appendingPathComponent(String(format: "frame_%02d.png", i)))) != nil { wrote += 1 }
            }
        }
        guard wrote > 0 else {                    // nothing actually copied — don't fake a success
            try? fm.removeItem(at: dir)
            throw AppearanceError.unwritableImage
        }
        try? folder.lastPathComponent.write(to: dir.appendingPathComponent("name.txt"),
                                            atomically: true, encoding: .utf8)
        activeSlug = slug                          // only after at least one file landed
        return AppearancePack(slug: slug, name: folder.lastPathComponent, dir: dir, thumbnail: thumbnail(in: dir))
    }

    /// Build a brand-new pack from loose images (filenames matched to roles,
    /// else filled in order), re-encoded as PNG, and make it active.
    @discardableResult
    static func newPack(fromImages sourceURLs: [URL]) throws -> AppearancePack {
        let assignments = assign(sourceURLs)
        guard !assignments.isEmpty else { throw AppearanceError.unreadableImage }

        let slug = uniqueSlug(preferred: "pack")
        let dir = packsDir.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var wrote = false
        for (role, src) in assignments {
            guard let image = NSImage(contentsOf: src), let png = image.pngData(maxPixelSize: 1024) else { continue }
            try png.write(to: dir.appendingPathComponent("\(role.rawValue).png"), options: .atomic)
            wrote = true
        }
        guard wrote else {
            try? FileManager.default.removeItem(at: dir)
            throw AppearanceError.unwritableImage
        }
        try? "我的形象".write(to: dir.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
        activeSlug = slug
        return AppearancePack(slug: slug, name: "我的形象", dir: dir, thumbnail: thumbnail(in: dir))
    }

    /// Delete a pack from the library. If it was active, fall back to default;
    /// also drop it from the roamer set so nothing dangles.
    static func deletePack(slug: String) {
        guard !slug.isEmpty else { return }
        try? FileManager.default.removeItem(at: packsDir.appendingPathComponent(slug, isDirectory: true))
        if activeSlug == slug { activeSlug = "" }
        if let i = roamerSlugs.firstIndex(of: slug) {
            var set = roamerSlugs
            set.remove(at: i)
            roamerSlugs = set
        }
    }

    // MARK: - Helpers

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func pngs(in dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
    }

    /// A filesystem-safe, currently-unused folder name derived from `preferred`.
    private static func uniqueSlug(preferred: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var base = String(preferred.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        if base.isEmpty { base = "pack" }

        let fm = FileManager.default
        var slug = base
        var n = 2
        while fm.fileExists(atPath: packsDir.appendingPathComponent(slug).path) {
            slug = "\(base)-\(n)"
            n += 1
        }
        return slug
    }

    private static func assign(_ urls: [URL]) -> [AppearanceRole: URL] {
        let sorted = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        var assigned: [AppearanceRole: URL] = [:]
        var unassigned: [URL] = []

        for url in sorted {
            let name = url.deletingPathExtension().lastPathComponent
            if let role = roleForFilename(name), assigned[role] == nil {
                assigned[role] = url
            } else {
                unassigned.append(url)
            }
        }

        for role in AppearanceRole.allCases where assigned[role] == nil {
            guard !unassigned.isEmpty else { break }
            assigned[role] = unassigned.removeFirst()
        }
        return assigned
    }

    private static func roleForFilename(_ filename: String) -> AppearanceRole? {
        let name = filename.lowercased()
        if containsAny(name, ["work", "working", "busy", "think", "coding", "工作", "干活", "忙", "思考"]) {
            return .work
        }
        if containsAny(name, ["rest", "sleep", "nap", "休息", "睡", "困"]) {
            return .rest
        }
        if containsAny(name, ["slack", "lazy", "fish", "break", "摸鱼", "偷懒", "发呆"]) {
            return .slack
        }
        if containsAny(name, ["drag", "hold", "lift", "stand", "拖拽", "拖动", "拎", "站立", "站起来"]) {
            return .drag
        }
        if containsAny(name, ["companion", "idle", "default", "normal", "陪伴", "日常", "默认"]) {
            return .companion
        }
        return nil
    }

    private static func containsAny(_ string: String, _ needles: [String]) -> Bool {
        needles.contains { string.contains($0) }
    }
}

enum AppearanceError: Error {
    case unreadableImage
    case unwritableImage
}

private extension NSImage {
    func pngData(maxPixelSize: CGFloat) -> Data? {
        let sourceSize = size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(1, maxPixelSize / max(sourceSize.width, sourceSize.height))
        let targetSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let targetRect = NSRect(origin: .zero, size: targetSize)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(targetSize.width.rounded())),
            pixelsHigh: max(1, Int(targetSize.height.rounded())),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        targetRect.fill()
        draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
