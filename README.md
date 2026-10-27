# Read Please

Read Please is a small Mac app that reads selected text aloud. Highlight text in any app — a webpage, an email, a PDF, a document — press a keyboard shortcut, and your Mac speaks it.

It lives in the menu bar, not the Dock, and stays out of the way until you need it.

> **This is a public beta.** It works and is used daily, but you may run into rough edges. Bug reports and suggestions are welcome — please open an issue.

## Download

**[Download the latest release →](https://github.com/studioetc/read-please/releases)**

Open the download and drag **Read Please** to your Applications folder.

### Opening it the first time

Because this is a beta, macOS will block it on first launch. To allow it (just once):

1. Open **Read Please** from Applications. When the warning appears, click **Done**.
2. Go to **System Settings → Privacy & Security** and scroll to the **Security** section.
3. Next to *"Read Please was blocked…"*, click **Open Anyway**, then enter your Mac password.

After that, it opens normally.

Or just run this command in terminal:
```
xattr -cr /Applications/ReadPlease.app
```

## Setup

When you first open the app it runs a quick setup:

- **Permission.** Read Please needs macOS **Accessibility** permission to see the text you've selected in other apps. The setup links you straight to the right place in System Settings.
- **Shortcut.** Pick keys for play/pause and stop, or keep the defaults (**Control + `** and **Control + 1**).
- **Voice.** Read Please uses the voices already built into your Mac. For more natural-sounding speech, you can download Apple's **Enhanced** or **Premium** voices from System Settings — the app shows you where.

You can revisit any of this later from **Settings**.

## Advanced Features

**Add more shortcuts.** Want more than the two defaults? A JSON file lets you map any number of extra shortcuts. Personally, I use F15 and F16, plus keys mapped to a spare mouse button in Karabiner-Elements — so I never have to reach for the keyboard.

**Custom pronunciation.** macOS voices usually pronounce words well, but some need a little help. Eg The voice I use sounds out the "th" in "github." You can fix quirks like these by editing the pronunciations JSON file.

> **Tip:** Not comfortable editing JSON? Paste it into your AI assistant of choice and tell it what you want changed — it'll make light work of it.

## Privacy

Read Please works **entirely on your Mac**. It only reads the text you've selected, speech is generated on-device, and nothing is sent anywhere.

## Requirements

- macOS 15 (Sequoia) or later
- Accessibility permission (granted during setup)

## Feedback

If something doesn't work or you have an idea, please [open an issue](https://github.com/studioetc/read-please-app/issues).

---

## Build from source

Read Please is built with Swift 6 and SwiftUI using Swift Package Manager. Xcode isn't required: the Command Line Tools (`xcode-select --install`) are enough.

```bash
swift build && ./run_tests.sh                            # dev build + tests
./build_app_staging.sh && open ReadPlease-Staging.app    # isolated test build
./build_app.sh && open ReadPlease.app                    # production build
```
