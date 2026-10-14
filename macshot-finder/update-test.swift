import Foundation
func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, asset: String = "MacShot-Finder.zip", external: Bool = false) -> ForkRelease {
    let base = external ? "https://example.com" : "https://github.com/TC023456-sys/Snaplet"
    return ForkRelease(tag_name: tag, html_url: "\(base)/releases/tag/\(tag)", draft: draft, prerelease: prerelease,
                       assets: [.init(name: asset, browser_download_url: "\(base)/releases/download/\(tag)/\(asset)")])
}
let candidates = [release("v99.0.0", asset: "Retina-Dummy.zip"), release("macshot-v4.3.0-finder.3"), release("macshot-v4.3.0-finder.10"), release("macshot-v4.4.0-finder.1", draft: true), release("macshot-v9.0.0-finder.1", external: true), release("macshot-v4.4.0-finder.1-beta.2", prerelease: true)]
precondition(ForkReleaseCatalog.latest(in: candidates, includeBeta: false)?.version.text == "4.3.0-finder.10")
precondition(ForkReleaseCatalog.latest(in: candidates, includeBeta: true)?.version.text == "4.4.0-finder.1-beta.2")
precondition(ForkVersion("4.3.0-finder.10")! > ForkVersion("4.3.0-finder.3")!)
precondition(ForkVersion("4.3.0-finder.3")! > ForkVersion("4.3.0-finder.3-beta.9")!)
for invalid in ["4.foo.3.0-finder.2", "4..3.0-finder.2", "4.3.0-finder.-1", "4.3.0-finder.2oops", "4.3.0"] { precondition(ForkVersion(invalid) == nil) }
precondition(ForkReleaseCatalog.latest(in: [release("v0.8.0", asset: "Retina-Dummy.zip")], includeBeta: false) == nil)
precondition(ForkReleaseCatalog.latest(in: [release("macshot-v4.3.0-finder.11", asset: "Retina-Dummy.zip")], includeBeta: false) == nil)
let oldRepoRelease = ForkRelease(tag_name: "macshot-v9.0.0-finder.1", html_url: "https://github.com/TC023456-sys/RetinaDummy/releases/tag/macshot-v9.0.0-finder.1", draft: false, prerelease: false, assets: [.init(name: "MacShot-Finder.zip", browser_download_url: "https://github.com/TC023456-sys/RetinaDummy/releases/download/macshot-v9.0.0-finder.1/MacShot-Finder.zip")])
precondition(ForkReleaseCatalog.latest(in: [oldRepoRelease], includeBeta: false) == nil)
print("PASS: own repository only; Retina releases excluded; numeric versions; stable/beta ordering; draft/external/malformed releases rejected")

if CommandLine.arguments.count > 1 {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let live = try JSONDecoder().decode([ForkRelease].self, from: data)
    let selected = ForkReleaseCatalog.latest(in: live, includeBeta: false)!
    precondition(selected.release.tag_name.hasPrefix("macshot-v"))
    print("Live GitHub selection:", selected.release.tag_name)
}
