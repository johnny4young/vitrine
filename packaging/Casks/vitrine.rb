# Homebrew cask template (CS-012). On each release, bump `version` and replace
# `sha256 :no_check` with the DMG's checksum (printed by scripts/build-dmg.sh).
cask "vitrine" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/johnny4young/vitrine/releases/download/v#{version}/Vitrine-#{version}.dmg"
  name "Vitrine"
  desc "Menu-bar app that turns code into beautiful images"
  homepage "https://github.com/johnny4young/vitrine"

  depends_on macos: ">= :sonoma"

  app "Vitrine.app"

  zap trash: [
    "~/Library/Preferences/app.vitrine.plist",
  ]
end
