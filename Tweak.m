#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <substrate.h>
#include <string.h>

/*
 * OBDeleven Update Bypass v1.0.4
 * Target: regular OBDeleven 1.11.0
 * Bundle: com.voltasit.obdeleven.ios.basic
 *
 * v1.0.4 stops patching IntroPresenter/state-machine branches entirely.
 * Instead it lets the app run its normal startup flow and only spoofs the
 * main bundle version/build values seen by the app's own update checker.
 *
 * This is intentionally scoped to the main OBDeleven bundle. Frameworks and
 * other bundles still receive their real Info.plist values.
 */

static NSString *const kSpoofedShortVersion = @"99.0.0";
static NSString *const kSpoofedBuildVersion = @"9999999999";

static BOOL isMainOBDelevenBundle(NSBundle *bundle) {
    if (!bundle) return NO;
    if (bundle != [NSBundle mainBundle]) return NO;
    return [[bundle bundleIdentifier] isEqualToString:@"com.voltasit.obdeleven.ios.basic"];
}

typedef id (*ObjectForInfoKeyIMP)(NSBundle *, SEL, NSString *);
static ObjectForInfoKeyIMP originalObjectForInfoKey = NULL;

static id spoofedObjectForInfoKey(NSBundle *self, SEL _cmd, NSString *key) {
    if (isMainOBDelevenBundle(self)) {
        if ([key isEqualToString:@"CFBundleVersion"]) {
            return kSpoofedBuildVersion;
        }
        if ([key isEqualToString:@"CFBundleShortVersionString"]) {
            return kSpoofedShortVersion;
        }
    }
    return originalObjectForInfoKey(self, _cmd, key);
}

typedef NSDictionary *(*InfoDictionaryIMP)(NSBundle *, SEL);
static InfoDictionaryIMP originalInfoDictionary = NULL;

static NSDictionary *spoofedInfoDictionary(NSBundle *self, SEL _cmd) {
    NSDictionary *original = originalInfoDictionary(self, _cmd);
    if (!isMainOBDelevenBundle(self) || !original) {
        return original;
    }

    NSMutableDictionary *copy = [original mutableCopy];
    copy[@"CFBundleVersion"] = kSpoofedBuildVersion;
    copy[@"CFBundleShortVersionString"] = kSpoofedShortVersion;
    return copy;
}

typedef CFTypeRef (*CFBundleGetValueIMP)(CFBundleRef, CFStringRef);
static CFBundleGetValueIMP originalCFBundleGetValue = NULL;

static CFTypeRef spoofedCFBundleGetValue(CFBundleRef bundle, CFStringRef key) {
    if (bundle == CFBundleGetMainBundle() && key) {
        if (CFEqual(key, CFSTR("CFBundleVersion"))) {
            return (__bridge CFTypeRef)kSpoofedBuildVersion;
        }
        if (CFEqual(key, CFSTR("CFBundleShortVersionString"))) {
            return (__bridge CFTypeRef)kSpoofedShortVersion;
        }
    }
    return originalCFBundleGetValue(bundle, key);
}

__attribute__((constructor))
static void OBDelevenUpdateBypassInit(void) {
    NSBundle *mainBundle = [NSBundle mainBundle];
    if (![[mainBundle bundleIdentifier] isEqualToString:@"com.voltasit.obdeleven.ios.basic"]) {
        return;
    }

    Class bundleClass = [NSBundle class];

    MSHookMessageEx(bundleClass,
                    @selector(objectForInfoDictionaryKey:),
                    (IMP)spoofedObjectForInfoKey,
                    (IMP *)&originalObjectForInfoKey);

    MSHookMessageEx(bundleClass,
                    @selector(infoDictionary),
                    (IMP)spoofedInfoDictionary,
                    (IMP *)&originalInfoDictionary);

    MSHookFunction((void *)CFBundleGetValueForInfoDictionaryKey,
                   (void *)spoofedCFBundleGetValue,
                   (void **)&originalCFBundleGetValue);

    NSLog(@"[OBDelevenUpdateBypass] v1.0.4 loaded; main bundle version spoof active");
}
