cask "windowshift" do
  version "0.2.0"
  sha256 :no_check # Replace with the release zip SHA256 when tagging v0.2.0

  url "https://github.com/lyu-xg/windowshift/releases/download/v#{version}/WindowShift-v#{version}-universal.zip"
  name "WindowShift"
  desc "Modifier-held window move/resize, keyboard layouts, and screen-edge snapping"
  homepage "https://github.com/lyu-xg/windowshift"

  depends_on macos: ">= :ventura"

  app "WindowShift.app"

  zap trash: [
    "~/.config/windowshift",
    "~/Library/Caches/dev.windowshift.app",
    "~/Library/Preferences/dev.windowshift.app.plist",
  ]
end
