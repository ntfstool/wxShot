# Draft cask. Submit to Homebrew/homebrew-cask once the repo has about 75 stars (their notability bar).
# Update version and sha256 on every release: shasum -a 256 wxShot.dmg
cask "wxshot" do
  version "0.1.0"
  sha256 "6f9caa01c8bb2dc9861aae7af2ea09d420960796223ac55cd5f9eb9455d91a74"

  url "https://github.com/ntfstool/wxShot/releases/download/v#{version}/wxShot.dmg"
  name "wxShot"
  desc "WeChat-style screenshot tool that works when WeChat is signed out"
  homepage "https://ntfstool.com/wxshot/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "wxShot.app"

  zap trash: "~/Library/Preferences/com.ntfstool.wxshot.plist"
end
