# OBDeleven Update Bypass

Rootless Dopamine/ElleKit tweak for **regular OBDeleven 1.11.0** (`com.voltasit.obdeleven.ios.basic`). It is not for OBDeleven VAG.

## What it fixes

OBDeleven 1.11.0 can stop at the full-screen **Update Required** page on launch.

Version **1.0.5** keeps the working v1.0.4 method. It does not force the app into a fake ready state and does not patch `IntroPresenter`, `AppUsabilityState`, jump tables, or `ForceUpdateViewController`.

Instead, the tweak lets OBDeleven's original startup/update logic run normally while making the old app report a newer version.

By default it reports:

- `CFBundleShortVersionString` = `2.10.0`
- `CFBundleVersion` = `2147483647`
- `x-mobile-app-version` request header = `2.10.0`

The short version is spoofed through the main `NSBundle` APIs and `CFBundleGetValueForInfoDictionaryKey`, while outgoing `NSURLSession` requests receive the same selected version in the `x-mobile-app-version` header.

## Configurable version

Version **1.0.5** adds an **OBDeleven Update Bypass** page in the iOS Settings app.

The **Spoofed Version** field defaults to `2.10.0`. If OBDeleven later requires a newer app version, enter that version in Settings instead of rebuilding the tweak.

The selected value is used for both:

- `CFBundleShortVersionString`
- `x-mobile-app-version`

The build-number spoof remains fixed at `2147483647`.

After changing the value, fully close OBDeleven and reopen it.

The Settings entry uses the official OBDeleven App Store icon when the release package is built.

## Why this method is used

Earlier builds experimented with directly modifying the app's update state and forcing `appIsReadyToBeUsed`. That could bypass the update screen but also skip normal startup work and leave OBDeleven sitting on its static launch icon.

v1.0.4 removed those control-flow patches. v1.0.5 keeps that same working approach and only adds configurability.

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

The GitHub Actions release build also retrieves the official OBDeleven App Store artwork and packages it as the Settings icon.

## Install

Install the rootless `.deb` in Sileo or Zebra, make sure tweak injection is allowed for OBDeleven, fully close OBDeleven from the app switcher, then reopen it.

This tweak bypasses the forced client-version gate. Old server APIs or individual features can still become incompatible with OBDeleven 1.11.0 independently of the update screen.
