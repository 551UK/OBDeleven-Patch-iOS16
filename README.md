# OBDeleven Update Bypass

Rootless Dopamine/ElleKit tweak for **regular OBDeleven 1.11.0** (`com.voltasit.obdeleven.ios.basic`). It is not for OBDeleven VAG.

## What was patched

The decrypted 1.11.0 binary contains the update decision in `ShouldUpdateApplicationUseCase.swift`. The code reads the installed `CFBundleVersion`, obtains the required build version, then compares the two.

At main-image offset `0x155BE8`, the original ARM64 instruction is:

```
14 A5 88 9A    cinc x20, x8, lt
```

When the installed build is lower than the required build, this changes the result to the forced-update state. The tweak replaces only that result-forming instruction with:

```
F4 03 08 AA    mov x20, x8
```

That preserves the same result used by the app when the installed version already satisfies the required version. It does **not** merely hide or dismiss the `Update Required` alert.

A four-byte signature check is performed before patching. If the installed executable is not the exact inspected build, the tweak does nothing rather than writing to an unknown address.

## Target

- App: OBDeleven 1.11.0 (regular/basic app)
- Bundle ID: `com.voltasit.obdeleven.ios.basic`
- iOS: 16.0+ rootless jailbreak
- Tested build target: iOS 16.2 Dopamine / ElleKit
- Architecture: arm64

## Build

Requires Theos with an iOS SDK:

```
make clean package FINALPACKAGE=1
```

## Install

Install the rootless `.deb` in Sileo or Zebra, fully kill OBDeleven, then reopen it.

This bypasses the client-side forced-version gate only. It cannot guarantee that old app APIs or server-side functionality remain compatible.
