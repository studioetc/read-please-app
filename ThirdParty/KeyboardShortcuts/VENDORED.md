# Vendored KeyboardShortcuts

Copy of [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 2.4.0
(`1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27`), MIT licensed — see `license`.

Local changes, so the app builds with the Command Line Tools alone (no Xcode.app):
- Removed the three `#Preview` blocks from `Sources/KeyboardShortcuts/Recorder.swift`.
  `#Preview` needs Xcode's `PreviewsMacros` plugin, which the Command Line Tools don't ship.
- Removed the example app, tests, and images, and the test target from `Package.swift`.

To update: copy the new release's `Sources/` and `Package.swift` over this folder, then reapply the changes above.
