#!/bin/bash
# Writes the ripple cask for a release into a homebrew-tap checkout and retires the source-build formula.
# Usage: scripts/update-cask.sh TAP_DIR VERSION SHA256
set -euo pipefail
TAP="$1" VERSION="$2" SHA="$3"
mkdir -p "$TAP/Casks"
cat > "$TAP/Casks/ripple.rb" <<CASK
cask "ripple" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/xinding33/ripple/releases/download/v#{version}/Ripple-#{version}.zip"
  name "Ripple"
  desc "Menu bar app that wakes your Macs together for Universal Control"
  homepage "https://github.com/xinding33/ripple"

  depends_on macos: :ventura

  app "Ripple.app"

  uninstall quit: "io.github.xinding33.ripple"

  zap trash: [
    "~/Library/LaunchAgents/com.xinding.Ripple.plist",
    "~/Library/LaunchAgents/io.github.xinding33.ripple.plist",
    "~/Library/Preferences/com.xinding.Ripple.plist",
    "~/Library/Preferences/io.github.xinding33.ripple.plist",
  ]
end
CASK
rm -f "$TAP/Formula/ripple.rb"
