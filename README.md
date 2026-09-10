# OBDeleven Update Bypass

Rootless Dopamine/ElleKit tweak for **regular OBDeleven 1.11.0** (`com.voltasit.obdeleven.ios.basic`). It is not for OBDeleven VAG.

## What it fixes

OBDeleven 1.11.0 can stop at the full-screen **Update Required** page even though the old app itself still launches on iOS 16.

Version 1.0.1 patches both parts of that launch gate:

1. The real build-version comparison inside `ShouldUpdateApplicationUseCase.swift`.
2. The final `AppUsabilityState.appUpdateIsRequired` dispatch used by `IntroPresenter`, which is the branch that opens `ForceUpdateViewController`.

This is not a visual tweak that simply hides the update screen. The update-required application state is redirected to the normal `appIsReadyToBeUsed` handling before the force-update controller is presented.

## Reverse-engineered locations

### Version decision

At main-image offset `0x155BE8`:

```
14 A5 88 9A    cinc x20, x8, lt
```

is replaced with:

```
F4 03 08 AA    mov x20, x8
```

### Final launch-state dispatch

Swift metadata identifies the no-payload `AppUsabilityState` cases as:

```
0  sessionTokenExpired
1  appIsReadyToBeUsed
2  appUpdateIsRequired
3  userPasswordChangeIsRequired
```

The state-2 jump-table entry at main-image offset `0x15EB40` normally points to the branch at `0x10015E944`. That branch resolves `ForceUpdateViewController` and opens the full-screen Update Required page.

Version 1.0.1 redirects only state 2 to the existing state-1 (`appIsReadyToBeUsed`) handler at `0x10015E908`.

Both patches perform exact four-byte checks first. If the installed executable does not match the inspected OBDeleven 1.11.0 build, the tweak leaves it untouched.

## Target

- App: OBDeleven 1.11.0 regular/basic app
- Bundle ID: `com.voltasit.obdeleven.ios.basic`
- Not for: OBDeleven VAG
- Jailbreak: rootless Dopamine / ElleKit
- iOS: 16.0+
- Architecture: arm64

## Build

Requires Theos with an iOS SDK:

```
make clean package FINALPACKAGE=1
```

## Install

Install the rootless `.deb` in Sileo or Zebra. Fully close OBDeleven from the app switcher and reopen it.

This only bypasses the client-side forced-update gate. Old server APIs or features may still stop working if OBDeleven has removed support for them server-side.
