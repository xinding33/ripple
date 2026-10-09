# Ripple

A small, free native macOS menu bar app that wakes your Macs together, so Universal Control can reach them without a keyboard or mouse plugged into each one. Run it on every Mac. When any Mac's display wakes, the others wake too.

## Install

Requires macOS 13+. Releases are universal (Apple silicon and Intel), signed with a Developer ID and notarized by Apple.

```sh
brew install --cask xinding33/tap/ripple
```

Or download `Ripple-x.y.z.zip` from the [latest release](https://github.com/xinding33/ripple/releases/latest), unzip it, and move `Ripple.app` to Applications.

Do this on each Mac. Open Ripple and allow local network access when macOS asks. Then choose **Open at Login** from Ripple's menu bar icon. `brew upgrade` quits Ripple; open it again afterwards.

To uninstall, turn off **Open at Login** and quit Ripple from its menu, then run `brew uninstall --cask ripple` (or delete `Ripple.app`).

If you installed the earlier source-build formula, switch with `brew uninstall ripple && brew install --cask xinding33/tap/ripple`, then open Ripple. It quits the old build and keeps your pairing code, settings and Open at Login. macOS asks for local network access once more.

To build it yourself instead, see [Build](#build).

## Set up

1. On one Mac, open **Settings…** from the menu bar icon, click **Generate**, then **Save Code**.
2. On each other Mac, enter the same code and click **Save Code**.

Each Mac's menu lists the other Macs it found:

- ✓ verified
- ⚠ pairing code doesn't match
- ? not responding

## Use

- **Wake Others When This Mac Wakes:** when this Mac's display wakes, Ripple wakes the other Macs' displays. A Mac woken by Ripple doesn't wake the others again.
- **Keep This Mac Awake:** prevents idle *system* sleep, so the Mac stays reachable. Its display still sleeps on its usual schedule. By default this applies only while on the power adapter.
- **Wake All Macs:** ⌃⌥⌘W by default. You can change the shortcut in Settings.

## How it works

Macs find each other with Bonjour on the local network and exchange small UDP messages. Each message is signed with HMAC-SHA256 using a key derived from the pairing code. A Mac rejects messages that are unsigned, signed with a different code, older than two minutes, or already seen. To wake a display, Ripple declares user activity, the same mechanism `caffeinate -u` uses.

The pairing code is kept in Ripple's preferences rather than the Keychain. Builds from source are ad-hoc signed, so the Keychain would ask for permission again after every rebuild. The code only authorizes waking displays.

## Build

Requires Xcode or the Swift command-line tools.

```sh
swift test
bash scripts/build.sh
open dist/Ripple.app
```

The build creates an ad-hoc signed universal app and ZIP for your own Macs. Set `SIGN_IDENTITY` to sign with your own certificate.

Logs: `log stream --predicate 'subsystem == "io.github.xinding33.ripple"'`. To try a pairing code without saving it, launch with `open dist/Ripple.app --args -pairingCode CODE`.

### Release

Pushing a `v*` tag runs `.github/workflows/release.yml`, which tests, signs with the hardened runtime, notarizes and staples the app, publishes `Ripple-x.y.z.zip` to a GitHub Release, and updates the cask in [xinding33/homebrew-tap](https://github.com/xinding33/homebrew-tap). It needs these secrets in a `release` environment restricted to `v*` tags: `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD` (the base64-encoded Developer ID Application certificate and its password), `NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID` (a base64-encoded App Store Connect API key), and `TAP_DEPLOY_KEY` (a deploy key with write access to the tap).

To produce the same notarized ZIP locally, save notary credentials once with `xcrun notarytool store-credentials wink-notary`, then run `bash scripts/release.sh`.

## Limitations

- All Macs must be on the same local network. Wi-Fi and Ethernet both work. Guest networks, client isolation, separate VLANs, and some VPNs block Bonjour.
- A Mac that is fully asleep can't receive a wake. Keep This Mac Awake prevents that, but a laptop with its lid closed and no external display sleeps anyway.
- Ripple wakes displays but can't get past the lock screen. Use Apple Watch unlock, or a longer "Require password after…" delay.
- iPads can't run Ripple.
