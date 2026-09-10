#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <substrate.h>

/*
 * OBDeleven Update Bypass v1.0.6
 * Target: regular OBDeleven 1.11.0
 * Bundle: com.voltasit.obdeleven.ios.basic
 *
 * Keeps the working v1.0.4 bypass path:
 *   - spoof CFBundleShortVersionString through NSBundle/CFBundle
 *   - spoof CFBundleVersion with the known-working high build value
 *   - spoof x-mobile-app-version on outgoing NSURLSession requests
 *
 * v1.0.6 fixes preference handling. The Settings value is now the single
 * source of truth for the runtime spoof. If it is set back to the app's real
 * installed version (1.11.0), every spoof is disabled and the original bundle
 * values/network request are allowed through unchanged.
 */

static NSString *const kPreferencesDomain = @"com.551.obdelevenupdatebypass";
static NSString *const kPreferencesChangedNotification =
    @"com.551.obdelevenupdatebypass/preferences.changed";
static NSString *const kDefaultSpoofedShortVersion = @"2.10.0";
static NSString *const kWorkingSpoofedBuildVersion = @"2147483647";
static NSString *const kMobileVersionHeader = @"x-mobile-app-version";

static NSBundle *gMainBundle = nil;
static BOOL gEnabled = YES;
static NSString *gSpoofedShortVersion = nil;
static NSString *gActualShortVersion = nil;

static BOOL isTargetBundle(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.voltasit.obdeleven.ios.basic"];
}

#pragma mark - Preferences

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

static id copyPreferenceValue(CFStringRef key) {
    CFPropertyListRef raw = CFPreferencesCopyValue(
        key,
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    if (!raw) return nil;
    return CFBridgingRelease(raw);
}

static void reloadPreferences(void) {
    CFPreferencesSynchronize(
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);

    id enabledValue = copyPreferenceValue(CFSTR("enabled"));
    id versionValue = copyPreferenceValue(CFSTR("spoofedVersion"));

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

        NSLog(@"[OBDelevenUpdateBypass] v1.0.6 loaded; enabled=%d selected=%@ actual=%@ active=%d build=%@ header=%@",
              gEnabled,
              currentSpoofedShortVersion(),
              gActualShortVersion,
              spoofingEnabled(),
              kWorkingSpoofedBuildVersion,
              kMobileVersionHeader);
    }
}
