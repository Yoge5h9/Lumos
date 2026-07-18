# Homebrew formula skeleton for Lumos — a calm, ambient macOS menu-bar app
# that shows Claude Code's 5-hour usage window as a notch glow + menu-bar LED.
#
# This is a BUILD-FROM-SOURCE formula, not a cask: Homebrew compiles Lumos
# locally on the user's machine via Swift Package Manager. Because the binary
# is never downloaded prebuilt, macOS Gatekeeper never flags it — no
# "unidentified developer" prompt, no Apple Developer account, no
# notarization. See DISTRIBUTION.md in the main repo for the full rationale.
#
# This file lives in the separate `homebrew-lumos` tap repo
# (`<github-user>/homebrew-lumos`), not in the main Lumos repo.
#
# PLACEHOLDERS below must be filled in at the first tagged release — see the
# inline comments.

class Lumos < Formula
  desc "Calm, ambient menu-bar glow for your Claude Code 5-hour usage window"
  homepage "https://github.com/PLACEHOLDER_GITHUB_USER/Lumos"

  # PLACEHOLDER: set once the first release is tagged, e.g.:
  #   url "https://github.com/PLACEHOLDER_GITHUB_USER/Lumos/archive/refs/tags/v0.1.0.tar.gz"
  #   sha256 "PLACEHOLDER_SHA256_OF_THE_RELEASE_TARBALL"
  url "https://github.com/PLACEHOLDER_GITHUB_USER/Lumos/archive/refs/tags/vPLACEHOLDER.tar.gz"
  sha256 "PLACEHOLDER_SHA256_64_HEX_CHARS_0000000000000000000000000000000000000000000000"
  license "MIT"

  # Head installs (`brew install --HEAD`) build straight off the default
  # branch — handy for testing the tap before a tagged release exists.
  head "https://github.com/PLACEHOLDER_GITHUB_USER/Lumos.git", branch: "main"

  depends_on xcode: ["14.0", :build] # supplies the Swift 5.9+ toolchain
  depends_on macos: :ventura         # LSMinimumSystemVersion == 13.0 (Ventura)

  def install
    # Build the `lumos` executable only — no full Xcode project involved.
    system "swift", "build", "-c", "release", "--disable-sandbox"

    # Assemble the menu-bar .app bundle the same way scripts/assemble-app.sh
    # does for local development, so both paths produce an identical layout.
    app_bundle = buildpath/"Lumos.app"
    contents   = app_bundle/"Contents"
    macos_dir  = contents/"MacOS"
    resources  = contents/"Resources"

    macos_dir.mkpath
    resources.mkpath

    cp buildpath/".build/release/lumos", macos_dir/"lumos"
    cp buildpath/"Resources/Info.plist", contents/"Info.plist"
    cp buildpath/"Resources/tips.json", resources/"tips.json"

    # Ad-hoc sign only (`-s -`) — deliberate: no Developer ID, no
    # notarization. This is what keeps the formula Gatekeeper-free.
    system "codesign", "-s", "-", "--force", "--deep", app_bundle

    prefix.install "Lumos.app"
    bin.install_symlink prefix/"Lumos.app/Contents/MacOS/lumos" => "lumos"
  end

  def caveats
    <<~EOS
      Lumos is installed but not yet wired up. Finish setup with:

        lumos setup

      This wires your Claude Code status line (non-destructively — your
      existing status line is backed up and wrapped, never replaced) so
      Lumos can read your 5-hour usage window locally. No network calls,
      no accounts, no API keys.

      To launch Lumos now:
        open #{opt_prefix}/Lumos.app

      To fully reverse setup later:
        lumos setup --uninstall
    EOS
  end

  test do
    # `lumos` is a long-running menu-bar agent with no CLI output today, so
    # the test only verifies the bundle assembled correctly rather than
    # invoking the binary (which would launch the app and hang the test).
    #
    # PLACEHOLDER: if/when a `--version` or `--help` flag is added to the
    # executable (Sources/lumos/main.swift), prefer asserting on its output
    # instead, e.g.:
    #   assert_match version.to_s, shell_output("#{bin}/lumos --version")
    assert_predicate prefix/"Lumos.app/Contents/MacOS/lumos", :exist?
    assert_predicate prefix/"Lumos.app/Contents/Info.plist", :exist?
  end
end
