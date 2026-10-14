import Cocoa

struct ForkRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browser_download_url: String
    }
    let tag_name: String
    let html_url: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

struct ForkVersion: Comparable, Sendable {
    let numbers: [Int]
    let beta: Int?
    let text: String

    init?(_ text: String) {
        guard text.range(of: #"^\d+\.\d+\.\d+-finder\.\d+(?:-beta\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        let pieces = text.components(separatedBy: "-finder.")
        guard pieces.count == 2 else { return nil }
        let base = pieces[0].split(separator: ".").compactMap { Int($0) }
        let fork = pieces[1].components(separatedBy: "-beta.")
        guard base.count == 3, fork.count <= 2, let revision = Int(fork[0]),
              base.allSatisfy({ $0 >= 0 }), revision >= 0 else { return nil }
        if fork.count == 2 {
            guard let value = Int(fork[1]), value >= 0 else { return nil }
            beta = value
        } else { beta = nil }
        numbers = base + [revision]
        self.text = text
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.numbers == rhs.numbers && lhs.beta == rhs.beta }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        switch (lhs.beta, rhs.beta) {
        case (.some(let a), .some(let b)): return a < b
        case (.some, .none): return true
        default: return false
        }
    }
}

enum ForkReleaseCatalog {
    static let repository = "TC023456-sys/Snaplet"
    static let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100")!
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!

    static func latest(in releases: [ForkRelease], includeBeta: Bool) -> (release: ForkRelease, version: ForkVersion)? {
        releases.compactMap { release -> (release: ForkRelease, version: ForkVersion)? in
            guard !release.draft, includeBeta || !release.prerelease,
                  release.tag_name.hasPrefix("macshot-v"),
                  let version = ForkVersion(String(release.tag_name.dropFirst("macshot-v".count))),
                  includeBeta || version.beta == nil,
                  release.html_url == "https://github.com/\(repository)/releases/tag/\(release.tag_name)",
                  release.assets.contains(where: {
                      $0.name == "MacShot-Finder.zip" &&
                      $0.browser_download_url == "https://github.com/\(repository)/releases/download/\(release.tag_name)/MacShot-Finder.zip"
                  }) else { return nil }
            return (release, version)
        }.max { $0.version < $1.version }
    }
}

/// Checks only this fork's GitHub releases. Download/install remains user initiated.
@MainActor
final class ForkUpdateService {
    static let shared = ForkUpdateService()
    private var timer: Timer?
    private var isChecking = false
    private let lastCheckKey = "finderForkLastSuccessfulUpdateCheck"

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(manual: false) }
        }
        check(manual: false)
    }

    func check(manual: Bool) {
        let defaults = UserDefaults.standard
        if !manual {
            guard defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true else { return }
            let last = defaults.double(forKey: lastCheckKey)
            guard Date().timeIntervalSince1970 - last >= 86400 else { return }
        }
        guard !isChecking else { return }
        isChecking = true
        let includeBeta = defaults.bool(forKey: "betaUpdatesEnabled")
        var request = URLRequest(url: ForkReleaseCatalog.apiURL)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("macshot-Finder", forHTTPHeaderField: "User-Agent")
        Task { [weak self] in
            guard let self else { return }
            defer { self.isChecking = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let releases = try JSONDecoder().decode([ForkRelease].self, from: data)
                guard let latest = ForkReleaseCatalog.latest(in: releases, includeBeta: includeBeta) else {
                    throw URLError(.cannotParseResponse)
                }
                defaults.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
                if !manual && !(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true) { return }
                let currentText = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                guard let current = ForkVersion(currentText) else { throw URLError(.cannotParseResponse) }
                if latest.version > current {
                    self.present(
                        message: self.text("发现新版本：\(latest.version.text)\n当前版本：\(currentText)\n更新来源：\(ForkReleaseCatalog.repository)",
                                           "New version: \(latest.version.text)\nInstalled: \(currentText)\nSource: \(ForkReleaseCatalog.repository)"),
                        url: URL(string: latest.release.html_url))
                } else if manual {
                    self.present(message: self.text("已是最新版本：\(currentText)\n更新来源：\(ForkReleaseCatalog.repository)",
                                                    "You are up to date: \(currentText)\nSource: \(ForkReleaseCatalog.repository)"), url: nil)
                }
            } catch {
                if manual {
                    self.present(message: self.text("暂时无法检查更新，请稍后重试或打开你的仓库下载页。\n\(error.localizedDescription)",
                                                    "Could not check for updates. Try again or open your repository's downloads page.\n\(error.localizedDescription)"),
                                 url: ForkReleaseCatalog.releasesURL)
                }
            }
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        LanguageManager.shared.resolvedLanguage.hasPrefix("zh") ? chinese : english
    }

    private func present(message: String, url: URL?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Check for Updates...")
        alert.informativeText = message
        if url != nil {
            alert.addButton(withTitle: L("Open Link"))
            alert.addButton(withTitle: L("Cancel"))
        } else { alert.addButton(withTitle: L("OK")) }
        if alert.runModal() == .alertFirstButtonReturn, let url { NSWorkspace.shared.open(url) }
    }
}
