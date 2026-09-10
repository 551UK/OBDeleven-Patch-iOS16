# OBDeleven Update Bypass

Rootless Dopamine/ElleKit tweak for **regular OBDeleven 1.11.0** (`com.voltasit.obdeleven.ios.basic`). It is not for OBDeleven VAG.

## What it fixes

OBDeleven 1.11.0 can stop at the full-screen **Update Required** page on launch.

Version **1.0.5** keeps the exact working v1.0.4 bypass method. It does not force the app into a fake ready state and does not patch `IntroPresenter`, `AppUsabilityState`, jump tables, or `ForceUpdateViewController`.

Instead, OBDeleven's normal startup/update logic is left alone while the tweak changes the version information it sees.

Default spoof values:

- `CFBundleShortVersionString` = `2.10.0`
- `CFBundleVersion` = `2147483647`
- `x-mobile-app-version` request header = `2.10.0`

The main bundle values are spoofed through:

- `-[NSBundle objectForInfoDictionaryKey:]`
- `-[NSBundle infoDictionary]`
- `CFBundleGetValueForInfoDictionaryKey`

The same selected app version is also inserted into outgoing `NSURLSession` requests as the `x-mobile-app-version` header. The tweak keeps the same request hooks used by the working v1.0.4 method.

## Settings

Version **1.0.5** adds a proper **OBDeleven Update Bypass** page in the iOS Settings app with the official OBDeleven icon.

Settings include:

- **Enabled** — master switch for all spoofing.
- **Spoofed Version** — defaults to `2.10.0`. This controls both `CFBundleShortVersionString` and `x-mobile-app-version`.
- **Spoofed Build** — defaults to `2147483647`. This controls `CFBundleVersion`.
- **Reset Working Defaults** — restores `2.10.0` and `2147483647`.
- **GitHub Repository** — opens this repo.

Changes are reloaded through a Darwin preferences notification. Fully close OBDeleven and reopen it after changing values so the app's startup update check runs again using the new spoof values.

If OBDeleven later requires a newer client version, you can enter the newer real version in **Spoofed Version** instead of recompiling the tweak.

## Why this method is used

Earlier builds experimented with directly changing the app's update state and forcing `appIsReadyToBeUsed`. That could remove the update page but also skip required startup work and leave OBDeleven sitting on its static launch icon.

v1.0.4 fixed that by stopping the control-flow patches and only spoofing the information used by the update check. v1.0.5 keeps that method and only adds safe configurability around it.

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

The GitHub Actions release build retrieves the official OBDeleven App Store artwork for the Settings icon, builds the rootless tweak and PreferenceBundle, validates the important spoof strings/files, and publishes the `.deb` to the matching GitHub release.

## Install

Install the rootless `.deb` in Sileo or Zebra, make sure tweak injection is allowed for OBDeleven, fully close OBDeleven from the app switcher, then reopen it.

This tweak bypasses the forced client-version gate. Old server APIs or individual features can still become incompatible with OBDeleven 1.11.0 independently of the update screen.
