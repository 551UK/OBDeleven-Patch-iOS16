#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <substrate.h>
#include <dlfcn.h>

/*
 * OBDeleven Update Bypass v1.0.7
 * Target: regular OBDeleven 1.11.0
 * Bundle: com.voltasit.obdeleven.ios.basic
 *
 * Keeps the proven v1.0.4 bypass path:
 *   - spoof CFBundleShortVersionString through NSBundle/CFBundle
 *   - spoof CFBundleVersion with the known-working high build value
 *   - spoof x-mobile-app-version on outgoing NSURLSession requests
 *
 * Settings are the single source of truth. Because OBDeleven is an App Store
 * app and therefore sandboxed, v1.0.7 also applies a small libSandy profile and
 * reads the jailbreak's rootless preferences plist directly. This avoids the
 * per-app cfprefsd container problem that made older Settings values appear to
 * save while the injected tweak continued using its defaults.
 */

static NSString *const kPreferencesDomain = @"com.551.obdelevenupdatebypass";
static NSString *const kPreferencesChangedNotification =
    @"com.551.obdelevenupdatebypass/preferences.changed";
static NSString *const kRootlessPreferencesPath =
    @"/var/jb/var/mobile/Library/Preferences/com.551.obdelevenupdatebypass.plist";
static NSString *const kLegacyPreferencesPath =
    @"/var/mobile/Library/Preferences/com.551.obdelevenupdatebypass.plist";
static const char *kLibSandyProfileName = "OBDelevenUpdateBypass_Preferences";

static NSString *const kDefaultSpoofedShortVersion = @"2.10.0";
static NSString *const kWorkingSpoofedBuildVersion = @"2147483647";
static NSString *const kMobileVersionHeader = @"x-mobile-app-version";

static NSBundle *gMainBundle = nil;
static BOOL gEnabled = YES;
static NSString *gSpoofedShortVersion = nil;
static NSString *gActualShortVersion = nil;
static BOOL gPreferenceSandboxAccessApplied = NO;
static void *gLibSandyHandle = NULL;

static BOOL isTargetBundle(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.voltasit.obdeleven.ios.basic"];
}

#pragma mark - Preferences

typedef int (*LibSandyApplyProfileFn)(const char *profileName);

static void applyPreferenceSandboxAccess(void) {
    if (gPreferenceSandboxAccessApplied) return;

    const char *paths[] = {
        "/var/jb/usr/lib/libsandy.dylib",
        "/usr/lib/libsandy.dylib",
        "libsandy.dylib",
        NULL
    };

    for (int i = 0; paths[i] != NULL && !gLibSandyHandle; i++) {
        gLibSandyHandle = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
    }

    if (!gLibSandyHandle) {
        NSLog(@"[OBDelevenUpdateBypass] libSandy could not be loaded: %s", dlerror());
        return;
    }

    LibSandyApplyProfileFn applyProfile =
        (LibSandyApplyProfileFn)dlsym(gLibSandyHandle, "libSandy_applyProfile");
    if (!applyProfile) {
        NSLog(@"[OBDelevenUpdateBypass] libSandy_applyProfile was not found");
        return;
    }

    int result = applyProfile(kLibSandyProfileName);
    if (result == 0) {
        gPreferenceSandboxAccessApplied = YES;
        NSLog(@"[OBDelevenUpdateBypass] preference sandbox profile applied");
    } else {
        NSLog(@"[OBDelevenUpdateBypass] preference sandbox profile failed: %d", result);
    }
}

static NSString *sanitizedVersionString(id candidate) {
    if (![candidate isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *trimmed = [(NSString *)candidate
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || trimmed.length > 32) {
        return nil;
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
    if ([trimmed rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound) {
        return nil;
    }

    if ([trimmed rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location == NSNotFound) {
        return nil;
    }

    return trimmed;
}

static NSDictionary *preferencesDictionaryFromDisk(void) {
    applyPreferenceSandboxAccess();

    NSArray<NSString *> *paths = @[
        kRootlessPreferencesPath,
        kLegacyPreferencesPath
    ];

    for (NSString *path in paths) {
        NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dictionary isKindOfClass:[NSDictionary class]]) {
            return dictionary;
        }
    }

    return nil;
}

static id copyPreferenceValue(NSString *key) {
    if (key.length == 0) return nil;

    // First read the actual jailbreak preference file. This is the important
    // path for sandboxed App Store processes on Dopamine/rootless.
    NSDictionary *diskPreferences = preferencesDictionaryFromDisk();
    id diskValue = diskPreferences[key];
    if (diskValue) {
        return diskValue;
    }

    // Keep a cfprefsd fallback for setups where the jailbreak exposes the
    // domain directly to the app process.
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPreferencesDomain);
    CFPropertyListRef raw = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPreferencesDomain);
    if (!raw) return nil;
    return CFBridgingRelease(raw);
}

static void reloadPreferences(void) {
    id enabledValue = copyPreferenceValue(@"enabled");
    id versionValue = copyPreferenceValue(@"spoofedVersion");

    BOOL enabled = enabledValue ? [enabledValue boolValue] : YES;
    NSString *version = sanitizedVersionString(versionValue) ?: kDefaultSpoofedShortVersion;

    @synchronized ([NSBundle class]) {
        gEnabled = enabled;
        gSpoofedShortVersion = [version copy];
    }
}

static NSString *currentSpoofedShortVersion(void) {
    @synchronized ([NSBundle class]) {
        return gSpoofedShortVersion ?: kDefaultSpoofedShortVersion;
    }
}

static BOOL spoofingEnabled(void) {
    @synchronized ([NSBundle class]) {
        if (!gEnabled) return NO;

        NSString *selected = gSpoofedShortVersion ?: kDefaultSpoofedShortVersion;
        if (gActualShortVersion.length > 0 && [selected isEqualToString:gActualShortVersion]) {
            return NO;
        }
        return YES;
    }
}

static void preferencesChanged(CFNotificationCenterRef center,
                               void *observer,
                               CFStringRef name,
                               const void *object,
                               CFDictionaryRef userInfo) {
    @autoreleasepool {
        reloadPreferences();
        NSLog(@"[OBDelevenUpdateBypass] Preferences reloaded; enabled=%d selected=%@ actual=%@ active=%d",
              gEnabled,
              currentSpoofedShortVersion(),
              gActualShortVersion,
              spoofingEnabled());
    }
}

#pragma mark - NSBundle version spoof

typedef id (*ObjectForInfoKeyIMP)(NSBundle *, SEL, NSString *);
static ObjectForInfoKeyIMP originalObjectForInfoKey = NULL;

static id spoofedObjectForInfoKey(NSBundle *self, SEL _cmd, NSString *key) {
    if (self == gMainBundle && spoofingEnabled()) {
        if ([key isEqualToString:@"CFBundleVersion"]) {
            return kWorkingSpoofedBuildVersion;
        }
        if ([key isEqualToString:@"CFBundleShortVersionString"]) {
            return currentSpoofedShortVersion();
        }
    }
    return originalObjectForInfoKey(self, _cmd, key);
}

typedef NSDictionary *(*InfoDictionaryIMP)(NSBundle *, SEL);
static InfoDictionaryIMP originalInfoDictionary = NULL;

static NSDictionary *spoofedInfoDictionary(NSBundle *self, SEL _cmd) {
    NSDictionary *original = originalInfoDictionary(self, _cmd);
    if (self != gMainBundle || !original || !spoofingEnabled()) {
        return original;
    }

    NSMutableDictionary *copy = [original mutableCopy];
    copy[@"CFBundleVersion"] = kWorkingSpoofedBuildVersion;
    copy[@"CFBundleShortVersionString"] = currentSpoofedShortVersion();
    return copy;
}

typedef CFTypeRef (*CFBundleGetValueIMP)(CFBundleRef, CFStringRef);
static CFBundleGetValueIMP originalCFBundleGetValue = NULL;

static CFTypeRef spoofedCFBundleGetValue(CFBundleRef bundle, CFStringRef key) {
    if (bundle == CFBundleGetMainBundle() && key && spoofingEnabled()) {
        if (CFEqual(key, CFSTR("CFBundleVersion"))) {
            return (__bridge CFTypeRef)kWorkingSpoofedBuildVersion;
        }
        if (CFEqual(key, CFSTR("CFBundleShortVersionString"))) {
            return (__bridge CFTypeRef)currentSpoofedShortVersion();
        }
    }
    return originalCFBundleGetValue(bundle, key);
}

#pragma mark - Network version header spoof

static NSURLRequest *requestBySpoofingVersionHeader(NSURLRequest *request) {
    if (!request || !spoofingEnabled()) {
        return request;
    }

    NSMutableURLRequest *mutable = [request mutableCopy];
    [mutable setValue:currentSpoofedShortVersion()
   forHTTPHeaderField:kMobileVersionHeader];
    return mutable;
}

typedef NSURLSessionDataTask *(*DataTaskRequestCompletionIMP)(
    NSURLSession *, SEL, NSURLRequest *,
    void (^)(NSData *, NSURLResponse *, NSError *));
static DataTaskRequestCompletionIMP originalDataTaskRequestCompletion = NULL;

static NSURLSessionDataTask *spoofedDataTaskRequestCompletion(
    NSURLSession *self,
    SEL _cmd,
    NSURLRequest *request,
    void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    return originalDataTaskRequestCompletion(
        self,
        _cmd,
        requestBySpoofingVersionHeader(request),
        completion);
}

typedef NSURLSessionDataTask *(*DataTaskRequestIMP)(
    NSURLSession *, SEL, NSURLRequest *);
static DataTaskRequestIMP originalDataTaskRequest = NULL;

static NSURLSessionDataTask *spoofedDataTaskRequest(
    NSURLSession *self,
    SEL _cmd,
    NSURLRequest *request) {
    return originalDataTaskRequest(
        self,
        _cmd,
        requestBySpoofingVersionHeader(request));
}

typedef NSURLSessionUploadTask *(*UploadTaskDataCompletionIMP)(
    NSURLSession *, SEL, NSURLRequest *, NSData *,
    void (^)(NSData *, NSURLResponse *, NSError *));
static UploadTaskDataCompletionIMP originalUploadTaskDataCompletion = NULL;

static NSURLSessionUploadTask *spoofedUploadTaskDataCompletion(
    NSURLSession *self,
    SEL _cmd,
    NSURLRequest *request,
    NSData *bodyData,
    void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    return originalUploadTaskDataCompletion(
        self,
        _cmd,
        requestBySpoofingVersionHeader(request),
        bodyData,
        completion);
}

static void installBundleSpoofs(void) {
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
}

static void installNetworkSpoofs(void) {
    Class sessionClass = [NSURLSession class];

    MSHookMessageEx(sessionClass,
                    @selector(dataTaskWithRequest:completionHandler:),
                    (IMP)spoofedDataTaskRequestCompletion,
                    (IMP *)&originalDataTaskRequestCompletion);

    MSHookMessageEx(sessionClass,
                    @selector(dataTaskWithRequest:),
                    (IMP)spoofedDataTaskRequest,
                    (IMP *)&originalDataTaskRequest);

    MSHookMessageEx(sessionClass,
                    @selector(uploadTaskWithRequest:fromData:completionHandler:),
                    (IMP)spoofedUploadTaskDataCompletion,
                    (IMP *)&originalUploadTaskDataCompletion);
}

__attribute__((constructor))
static void OBDelevenUpdateBypassInit(void) {
    @autoreleasepool {
        if (!isTargetBundle()) return;

        gMainBundle = [NSBundle mainBundle];
        gActualShortVersion = [[gMainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] copy];

        applyPreferenceSandboxAccess();
        reloadPreferences();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            preferencesChanged,
            (__bridge CFStringRef)kPreferencesChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        installBundleSpoofs();
        installNetworkSpoofs();

        NSLog(@"[OBDelevenUpdateBypass] v1.0.7 loaded; enabled=%d selected=%@ actual=%@ active=%d build=%@ header=%@ prefsFileAccess=%d",
              gEnabled,
              currentSpoofedShortVersion(),
              gActualShortVersion,
              spoofingEnabled(),
              kWorkingSpoofedBuildVersion,
              kMobileVersionHeader,
              gPreferenceSandboxAccessApplied);
    }
}
