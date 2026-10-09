# Ripple

A small, free native macOS menu bar app that wakes your Macs together, so Universal Control can reach them without a keyboard or mouse plugged into each one. Run it on every Mac. When any Mac's display wakes, the others wake too.

## Install

Requires macOS 13+ and the Xcode command line tools. Homebrew builds Ripple on your Mac, so there's no Gatekeeper warning.

```sh
brew install xinding33/tap/ripple
open "$(brew --prefix)/opt/ripple/Ripple.app"
```

Do this on each Mac. Allow local network access when macOS asks. Then choose **Open at Login** from Ripple's menu bar icon. Quit Ripple before `brew upgrade ripple`, then open it again.

To uninstall, turn off **Open at Login** and quit Ripple from its menu, then run `brew uninstall ripple`.

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

The pairing code is kept in Ripple's preferences rather than the Keychain. Homebrew builds are ad-hoc signed, so the Keychain would ask for permission again after every upgrade. The code only authorizes waking displays.

## Build

Requires Xcode or the Swift command-line tools.

```sh
swift test
bash scripts/build.sh
open dist/Ripple.app
```

The build creates an ad-hoc signed app and ZIP for the current Mac architecture. It is not notarized for distribution to other Macs. Set `SIGN_IDENTITY` to sign with your own certificate.

Logs: `log stream --predicate 'subsystem == "com.xinding.Ripple"'`. To try a pairing code without saving it, launch with `open dist/Ripple.app --args -pairingCode CODE`.

## Limitations

- All Macs must be on the same local network. Wi-Fi and Ethernet both work. Guest networks, client isolation, separate VLANs, and some VPNs block Bonjour.
- A Mac that is fully asleep can't receive a wake. Keep This Mac Awake prevents that, but a laptop with its lid closed and no external display sleeps anyway.
- Ripple wakes displays but can't get past the lock screen. Use Apple Watch unlock, or a longer "Require password after…" delay.
- iPads can't run Ripple.
- macOS may ask for local network access again after `brew upgrade`.
