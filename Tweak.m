#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <substrate.h>

/*
 * OBDeleven Update Bypass v1.0.4
 * Target: regular OBDeleven 1.11.0
 * Bundle: com.voltasit.obdeleven.ios.basic
 *
 * No IntroPresenter/state-machine branches are patched in this version.
 * The app is allowed to run its normal startup sequence. Only the version
 * values returned for the main OBDeleven bundle are spoofed so the app's own
 * update checker can naturally decide that no forced update is required.
 */

static NSString *const kSpoofedShortVersion = @"2.10.0";
static NSString *const kSpoofedBuildVersion = @"9999999999";
static NSBundle *gMainBundle = nil;

typedef id (*ObjectForInfoKeyIMP)(NSBundle *, SEL, NSString *);
static ObjectForInfoKeyIMP originalObjectForInfoKey = NULL;

static id spoofedObjectForInfoKey(NSBundle *self, SEL _cmd, NSString *key) {
    if (self == gMainBundle) {
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
    if (self != gMainBundle || !original) {
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
    @autoreleasepool {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *realBundleID = [bundle bundleIdentifier];
        if (![realBundleID isEqualToString:@"com.voltasit.obdeleven.ios.basic"]) {
            return;
        }

        gMainBundle = bundle;
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

        NSLog(@"[OBDelevenUpdateBypass] v1.0.4 loaded; spoofing version %@ build %@",
              kSpoofedShortVersion,
              kSpoofedBuildVersion);
    }
}
