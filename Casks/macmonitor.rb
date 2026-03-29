# Homebrew Cask formula for MacMonitor
# Hosted directly in the MacMonitor repo — no separate tap repo needed.
#
# Install:
#   brew tap ryyansafar/macmonitor https://github.com/ryyansafar/MacMonitor
#   brew install --cask macmonitor
#
# Upgrade (after a new GitHub Release is published):
#   brew upgrade --cask macmonitor

cask "macmonitor" do
  version "1.1.1"
  sha256 "PLACEHOLDER_SHA256_UPDATED_AUTOMATICALLY_BY_CI"

  url "https://github.com/ryyansafar/MacMonitor/releases/download/v#{version}/MacMonitor-#{version}.dmg"
  name "MacMonitor"
  desc "Real-time Apple Silicon system monitor — menu bar app and desktop widget"
  homepage "https://github.com/ryyansafar/MacMonitor"

  # Apple Silicon only — M1 / M2 / M3 / M4
  depends_on macos:  ">= :ventura"
  depends_on arch:   :arm64

  app "Macmonitor.app"

  # Post-install: install mactop if missing (powers GPU, temps, power rails)
  postflight do
    system_command "/bin/bash",
                   args: ["-c", "command -v mactop >/dev/null 2>&1 || /opt/homebrew/bin/brew install mactop"],
                   sudo: false
  end

  # Uninstall: remove all traces
  uninstall quit: "rybo.Macmonitor"

  zap trash: [
    "~/Library/Preferences/rybo.Macmonitor.plist",
    "~/Library/Application Support/Macmonitor",
    "~/Library/Caches/rybo.Macmonitor",
    "/etc/sudoers.d/macmonitor",
  ]
end
