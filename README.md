# OBDeleven Update Bypass

Rootless Dopamine/ElleKit tweak for **regular OBDeleven 1.11.0** (`com.voltasit.obdeleven.ios.basic`). It is not for OBDeleven VAG.

## What it fixes

OBDeleven 1.11.0 can stop at the full-screen **Update Required** page on launch.

Version **1.0.6** keeps the proven v1.0.4 bypass method and fixes the Settings wiring. It does not force the app into a fake ready state and does not patch `IntroPresenter`, `AppUsabilityState`, jump tables, or `ForceUpdateViewController`.

Instead, OBDeleven's normal startup/update logic is left alone while the tweak changes the version information it sees.

Working spoof values when the default **2.10.0** is selected:

- `CFBundleShortVersionString` = `2.10.0`
- `CFBundleVersion` = `2147483647`
- `x-mobile-app-version` request header = `2.10.0`

The main bundle values are spoofed through:

- `-[NSBundle objectForInfoDictionaryKey:]`
- `-[NSBundle infoDictionary]`
- `CFBundleGetValueForInfoDictionaryKey`

The selected app version is also inserted into outgoing `NSURLSession` requests as the `x-mobile-app-version` header.

## Settings

Version **1.0.6** includes a proper **OBDeleven Update Bypass** page in the iOS Settings app.

Settings include:

- **Enabled** — master switch for all spoofing.
- **Spoofed Version** — defaults to `2.10.0` and is the source of truth for the runtime bypass.
- **Reset Working Default** — restores `2.10.0`.
- **Respring** — resprings directly from the tweak settings page.
- **GitHub Repository** — opens this repo.

The Settings page now writes directly to the same CFPreferences domain that the injected tweak reads and posts a Darwin notification after every change.

If **Spoofed Version** is set back to the app's real installed version (`1.11.0`), the tweak disables every spoof at runtime. That means the original `CFBundleShortVersionString`, original `CFBundleVersion`, and original outgoing network request are used again. This makes it easy to verify the preference is really taking effect: setting `1.11.0` should allow the normal **Update Required** gate to return, while setting `2.10.0` turns the bypass back on.

When a newer version than the installed app is selected, the tweak keeps the known-working `2147483647` `CFBundleVersion` spoof internally while using your selected value for `CFBundleShortVersionString` and `x-mobile-app-version`.

Fully close OBDeleven and reopen it after changing the version so its startup update check runs again.

If OBDeleven later requires a newer client version, enter the newer real version in **Spoofed Version** instead of recompiling the tweak.

## Settings icon

The GitHub Actions build downloads the official OBDeleven artwork and resizes it to the normal PreferenceLoader icon size before packaging, so it no longer appears oversized in Settings.

## Why this method is used

Earlier builds experimented with directly changing the app's update state and forcing `appIsReadyToBeUsed`. That could remove the update page but also skip required startup work and leave OBDeleven sitting on its static launch icon.

v1.0.4 fixed that by stopping the control-flow patches and only spoofing the information used by the update check. v1.0.6 keeps that working approach and fixes the preference layer around it.

## Target

- App: regular/basic OBDeleven 1.11.0
- Bundle ID: `com.voltasit.obdeleven.ios.basic`
- Not for: OBDeleven VAG
- Jailbreak: rootless Dopamine / ElleKit
- iOS: 16.0+
- Architecture: arm64

## Build

```sh
make clean package FINALPACKAGE=1
```

The GitHub Actions release build retrieves the official OBDeleven App Store artwork, resizes the Settings icon, builds the rootless tweak and PreferenceBundle, validates the important spoof strings/files, and publishes the `.deb` to the matching GitHub release.

## Install

Install the rootless `.deb` in Sileo or Zebra, make sure tweak injection is allowed for OBDeleven, fully close OBDeleven from the app switcher, then reopen it.

This tweak bypasses the forced client-version gate. Old server APIs or individual features can still become incompatible with OBDeleven 1.11.0 independently of the update screen.
