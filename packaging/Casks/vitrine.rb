# Homebrew cask for Vitrine (CS-012, CS-063).
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
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/johnny4young/vitrine/releases/download/v#{version}/Vitrine-#{version}.dmg"
  name "Vitrine"
  desc "Menu-bar app that turns code into beautiful images"
  homepage "https://github.com/johnny4young/vitrine"

  # A stable release-URL pattern exists (GitHub release tags), so livecheck can
  # track new versions straight from the releases page (CS-063).
  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Vitrine.app"

  zap trash: [
    "~/Library/Application Support/Vitrine",
    "~/Library/Caches/app.vitrine",
    "~/Library/HTTPStorages/app.vitrine",
    "~/Library/Preferences/app.vitrine.plist",
  ]
end
