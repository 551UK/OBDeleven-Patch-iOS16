# OBDeleven Update Bypass

Rootless Dopamine/ElleKit tweak for **regular OBDeleven 1.11.0** (`com.voltasit.obdeleven.ios.basic`). It is not for OBDeleven VAG.

## What it fixes

OBDeleven 1.11.0 can stop at the full-screen **Update Required** page on launch.

Version 1.0.2 uses three client-side bypasses for the exact inspected 1.11.0 build:

1. Patches the build-version result in `ShouldUpdateApplicationUseCase.swift`.
2. Forces `IntroPresenter.startUsabilityStateCheck()` to dispatch state `1` (`appIsReadyToBeUsed`) instead of state `2` (`appUpdateIsRequired`).
3. Hooks UIKit presentation as a final failsafe and refuses to present/push `ForceUpdateViewController`.

The binary patches perform exact four-byte checks before writing, so an unknown OBDeleven build is not blindly modified.

## Key reverse-engineered locations

### Version decision

Main-image offset `0x155BE8`:

```
14 A5 88 9A    cinc x20, x8, lt
```

becomes:

```
F4 03 08 AA    mov x20, x8
```

### Launch usability state

`IntroPresenter.startUsabilityStateCheck()` loads the returned state at main-image offset `0x15E778`:

```
D7 4E 40 F9    ldr x23, [x22, #0x98]
```

Version 1.0.2 replaces that with:

```
37 00 80 D2    mov x23, #1
```

State `1` is the app's normal `appIsReadyToBeUsed` path. State `2` is `appUpdateIsRequired`, which leads to `ForceUpdateViewController`.

The older v1.0.1 jump-table redirect at `0x15EB40` is retained as another binary failsafe.

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

## Install

Install the rootless `.deb` in Sileo or Zebra, fully close OBDeleven from the app switcher, then reopen it.

If v1.0.2 still shows the untouched Update Required controller, first verify that tweak injection is actually enabled for OBDeleven (for example in Choicy), because the UIKit failsafe runs only when this dylib is loaded into the app.

This tweak only bypasses the client-side forced-update gate. Old server APIs or features may still be incompatible with OBDeleven 1.11.0.
