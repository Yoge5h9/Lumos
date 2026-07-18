# homebrew-lumos

Homebrew tap for [Lumos](https://github.com/PLACEHOLDER_GITHUB_USER/Lumos) — a calm, ambient
menu-bar glow for your Claude Code 5-hour usage window. This tap builds Lumos from source on
your machine, so there's no Gatekeeper prompt and no Apple Developer account involved.

## Install

```sh
brew tap <user>/lumos
brew install lumos
lumos setup
```

(or in one line: `brew install <user>/lumos/lumos`)

`lumos setup` wires up your Claude Code status line non-destructively (backed up, wrapped,
never replaced) so Lumos can read your usage data locally. No accounts, no network calls.

## Update

```sh
brew upgrade lumos
```

## Updating tips

The rotating tips shown in Tip notifications live in `Resources/tips.json` in the main
Lumos repo (a plain JSON array of `{id, title, body}`), not in Swift code. To refresh the
copy: edit `Resources/tips.json` there, using `TIPS-RESEARCH.md` as the curation source for
new candidates, then cut a release as usual — the next `brew upgrade lumos` picks it up.
No Swift changes or rebuild logic needed. If `tips.json` is ever missing or unparseable,
Lumos falls back to its small built-in default set, so a bad edit degrades gracefully
rather than crashing.

## Uninstall

```sh
lumos setup --uninstall
brew uninstall lumos
```
