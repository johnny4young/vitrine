# Homebrew cask for Vitrine.
#
# This file is the source template that lives in the app repo; the released cask
# lives in the tap (johnny4young/homebrew-tap, `Casks/vitrine.rb`). On each
# release, the cask in the tap is bumped to the new `version` and its `sha256` is
# set to the checksum of the published DMG (printed and stored by the release
# workflow, `.github/workflows/release.yml`). See docs/RELEASING.md.
#
# The placeholder `sha256` below is a syntactically valid 64-hex-digit value so
# the template passes `brew audit --cask --strict`; the release process replaces
# it with the real DMG checksum before the tap commit. Never publish this
# placeholder to the tap.
cask "vitrine" do
  version "0.24.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/johnny4young/vitrine/releases/download/v#{version}/Vitrine-#{version}.dmg"
  name "Vitrine"
  desc "Menu-bar app that turns code into beautiful images"
  homepage "https://vitrineframe.app/"

  # A stable release-URL pattern exists (GitHub release tags), so livecheck can
  # track new versions straight from the releases page.
  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle keeps the installed app current in place, so Homebrew
  # should not flag user-updated copies as outdated.
  auto_updates true
  depends_on macos: :sonoma

  app "Vitrine.app"
  # The `vitrine` command-line renderer ships embedded in the app bundle;
  # this symlinks it onto PATH so a cask install gets the CLI too.
  # It is named `vitrine-cli` inside the bundle (a `vitrine` sibling would
  # collide with the `Vitrine` app executable on case-insensitive APFS) and
  # surfaces on PATH under its real name via `target:`.
  binary "#{appdir}/Vitrine.app/Contents/MacOS/vitrine-cli", target: "vitrine"

  zap trash: [
    "~/Library/Application Support/Vitrine",
    "~/Library/Caches/com.johnny4young.vitrine",
    "~/Library/HTTPStorages/com.johnny4young.vitrine",
    "~/Library/Preferences/com.johnny4young.vitrine.plist",
  ]
end
