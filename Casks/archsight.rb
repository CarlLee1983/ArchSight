cask "archsight" do
  version "0.1.0"
  sha256 "54cdb7d3630ae4d9daed7916d9855a663c7c8495c071d5463f9e291e0659167b"

  url "https://github.com/CarlLee1983/ArchSight/releases/download/v#{version}/ArchSight-#{version}.zip"
  name "ArchSight"
  desc "Read-only source-code observation tool for senior engineers"
  homepage "https://github.com/CarlLee1983/ArchSight"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "ArchSight.app"

  zap trash: [
    "~/Library/Application Support/ArchSight",
    "~/Library/Caches/com.cmg.archsight",
    "~/Library/HTTPStorages/com.cmg.archsight",
    "~/Library/Preferences/com.cmg.archsight.plist",
    "~/Library/Saved Application State/com.cmg.archsight.savedState",
  ]

  caveats <<~EOS
    ArchSight is ad-hoc signed and not notarized by Apple, so Gatekeeper
    blocks the first launch. After installing, clear the quarantine flag once:

      xattr -dr com.apple.quarantine "#{appdir}/ArchSight.app"

    (Or open it the first time via right-click > Open, or via
    System Settings > Privacy & Security > "Open Anyway".)

    Symbol navigation uses optional language servers, discovered lazily and
    never required to open or browse code:

      brew install gopls                                       # Go
      npm  install -g typescript-language-server typescript    # TypeScript
      # Swift: sourcekit-lsp ships with Xcode
  EOS
end
