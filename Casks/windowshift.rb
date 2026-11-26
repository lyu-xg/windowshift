cask "windowshift" do
  version "0.2.0"
  sha256 "4f640e6dc9ebf3d3b7e092863f7b9c8ea6d9f4da8cc048233d5a18e264ea7772"

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
