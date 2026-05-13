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
  version "2.0.1"
  sha256 "4c08f2346db3ae683aad4570ab1d2ae9cc5c431748dd363d52a6c72d0327a5cf"

  url "https://github.com/ryyansafar/MacMonitor/releases/download/v#{version}/MacMonitor-#{version}.dmg"
  name "MacMonitor"
  desc "Real-time Apple Silicon system monitor — menu bar app and desktop widget"
  homepage "https://github.com/ryyansafar/MacMonitor"

  # Apple Silicon only — M1 through M5+, macOS 13 Ventura and later
  depends_on macos: ">= :ventura"
  depends_on arch:  :arm64

  app "Macmonitor.app"

  # Post-install: install the privileged helper that powers GPU, temps, and power rails.
  # The helper reads IOReport and SMC directly — no third-party tools required.
  postflight do
    helper_dir  = "/Users/Shared/MacMonitor"
    helper_path = "#{helper_dir}/macmonitor-helper"

    # Only install if the helper isn't already present and working
    unless File.executable?(helper_path)
      system_command "/bin/mkdir", args: ["-p", helper_dir], sudo: true
      system_command "/bin/cp",
                     args: ["#{staged_path}/Macmonitor.app/Contents/MacOS/macmonitor-helper", helper_path],
                     sudo: true
      system_command "/bin/chmod", args: ["755", helper_path], sudo: true
    end
  end

  caveats <<~EOS
    MacMonitor v2.0 no longer requires mactop.
    If you had it installed for MacMonitor, you can safely remove it:
      brew uninstall mactop

    What's new: CPU die hotspot · fan RPM · chip variant (M2 Pro, M2 Max…)
    Changelog: https://github.com/ryyansafar/MacMonitor/blob/main/CHANGELOG.md
  EOS

  # Uninstall: quit app and remove helper
  uninstall quit:   "rybo.Macmonitor",
            delete: "/Users/Shared/MacMonitor/macmonitor-helper"

  zap trash: [
    "~/Library/Preferences/rybo.Macmonitor.plist",
    "~/Library/Application Support/Macmonitor",
    "~/Library/Caches/rybo.Macmonitor",
    "/etc/sudoers.d/macmonitor-helper",
  ]
end
