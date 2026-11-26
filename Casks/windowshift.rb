cask "windowshift" do
  version "0.2.1"
  sha256 "7f4e9395ba73ab0354a1543fb08340603b8c44f7d95bf9367d6b7dbd217d9f70"

  url "https://github.com/lyu-xg/windowshift/releases/download/v#{version}/WindowShift-v#{version}-universal.zip"
  name "WindowShift"
  desc "Modifier-held window move/resize, keyboard layouts, and screen-edge snapping"
  homepage "https://github.com/lyu-xg/windowshift"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "WindowShift.app"

  zap trash: [
    "~/.config/windowshift",
    "~/Library/Caches/dev.windowshift.app",
    "~/Library/Preferences/dev.windowshift.app.plist",
  ]
end
