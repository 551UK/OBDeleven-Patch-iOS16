# eBay Compat 14

Rootful iOS 14 compatibility patch for the old eBay app.

The supplied IPA is not really eBay 6.267.0 internally: only the main `Info.plist` says 6.267.0. Its embedded eBay frameworks still identify themselves as **6.96.0 / build 3839**, and the binary was built with the iOS 15.5 SDK. This mismatch is one reason a simple `Info.plist` version change is not enough.

This tweak spoofs eBay to **6.272.0** at runtime across:

- the main eBay bundle and eBay-owned framework bundles
- `CFBundleShortVersionString` and `CFBundleVersion`
- eBay mobile-version headers and user-agent strings
- outgoing URL query parameters that carry app/build/OS versions
- UTF-8 request bodies containing the old app version
- `NSURLSession`, `NSURLConnection`, and `WKWebView` requests

It also advertises iOS **18.0 only in outgoing compatibility metadata**. It does **not** globally fake the device's iOS version, so app code still sees the real iOS 14 system APIs.

Target: **rootful iOS 14.x** / `com.ebay.iphone`.

This can restore server-rejected sections, but it cannot add code or API support that only exists in the modern eBay app.
