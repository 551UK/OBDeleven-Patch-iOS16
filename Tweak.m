#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <substrate.h>

/*
 * OBDeleven Update Bypass v1.0.5
 * Target: regular OBDeleven 1.11.0
 * Bundle: com.voltasit.obdeleven.ios.basic
 *
 * Keeps the working v1.0.4 strategy: do not patch IntroPresenter,
 * AppUsabilityState, jump tables, or ForceUpdateViewController.
 *
 * The spoofed short version is now configurable from Settings. The default
 * remains 2.10.0. The high build number stays fixed at 2147483647.
 */

static NSString *const kPreferencesDomain = @"com.551.obdelevenupdatebypass";
static NSString *const kPreferencesChangedNotification = @"com.551.obdelevenupdatebypass/preferences.changed";
static NSString *const kDefaultSpoofedShortVersion = @"2.10.0";
/* High, but still safe for signed 32-bit code paths. */
static NSString *const kSpoofedBuildVersion = @"2147483647";
static NSString *const kMobileVersionHeader = @"x-mobile-app-version";

static NSBundle *gMainBundle = nil;
static NSString *gSpoofedShortVersion = nil;

static BOOL isTargetBundle(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.voltasit.obdeleven.ios.basic"];
}

#pragma mark - Preferences

static NSString *sanitizedVersionString(NSString *candidate) {
    if (![candidate isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *trimmed = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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

static NSString *readConfiguredSpoofedVersion(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPreferencesDomain);

    CFPropertyListRef rawValue = CFPreferencesCopyAppValue(CFSTR("spoofedVersion"),
                                                           (__bridge CFStringRef)kPreferencesDomain);
    NSString *candidate = nil;

    if (rawValue) {
        if (CFGetTypeID(rawValue) == CFStringGetTypeID()) {
            candidate = [(__bridge NSString *)rawValue copy];
        }
        CFRelease(rawValue);
    }

    NSString *sanitized = sanitizedVersionString(candidate);
    return sanitized ?: kDefaultSpoofedShortVersion;
}

static void reloadPreferences(void) {
    NSString *newVersion = readConfiguredSpoofedVersion();
    @synchronized([NSBundle class]) {
        gSpoofedShortVersion = [newVersion copy];
    }
}

static NSString *currentSpoofedShortVersion(void) {
    @synchronized([NSBundle class]) {
        return gSpoofedShortVersion ?: kDefaultSpoofedShortVersion;
    }
}

static void preferencesChanged(CFNotificationCenterRef center,
                               void *observer,
                               CFStringRef name,
                               const void *object,
                               CFDictionaryRef userInfo) {
    reloadPreferences();
    NSLog(@"[OBDelevenUpdateBypass] Preferences reloaded; version=%@",
          currentSpoofedShortVersion());
}

#pragma mark - NSBundle version spoof

typedef id (*ObjectForInfoKeyIMP)(NSBundle *, SEL, NSString *);
static ObjectForInfoKeyIMP originalObjectForInfoKey = NULL;

static id spoofedObjectForInfoKey(NSBundle *self, SEL _cmd, NSString *key) {
    if (self == gMainBundle) {
        if ([key isEqualToString:@"CFBundleVersion"]) {
            return kSpoofedBuildVersion;
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
    if (self != gMainBundle || !original) {
        return original;
    }

    NSMutableDictionary *copy = [original mutableCopy];
    copy[@"CFBundleVersion"] = kSpoofedBuildVersion;
    copy[@"CFBundleShortVersionString"] = currentSpoofedShortVersion();
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
            return (__bridge CFTypeRef)currentSpoofedShortVersion();
        }
    }
    return originalCFBundleGetValue(bundle, key);
}

#pragma mark - Network version header spoof

static NSURLRequest *requestBySpoofingVersionHeader(NSURLRequest *request) {
    if (!request) return request;

    NSMutableURLRequest *mutable = [request mutableCopy];
    [mutable setValue:currentSpoofedShortVersion() forHTTPHeaderField:kMobileVersionHeader];
    return mutable;
}

typedef NSURLSessionDataTask *(*DataTaskRequestCompletionIMP)(NSURLSession *, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
static DataTaskRequestCompletionIMP originalDataTaskRequestCompletion = NULL;

static NSURLSessionDataTask *spoofedDataTaskRequestCompletion(NSURLSession *self,
                                                               SEL _cmd,
                                                               NSURLRequest *request,
                                                               void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    return originalDataTaskRequestCompletion(self, _cmd,
                                             requestBySpoofingVersionHeader(request),
                                             completion);
}

typedef NSURLSessionDataTask *(*DataTaskRequestIMP)(NSURLSession *, SEL, NSURLRequest *);
static DataTaskRequestIMP originalDataTaskRequest = NULL;

static NSURLSessionDataTask *spoofedDataTaskRequest(NSURLSession *self,
                                                     SEL _cmd,
                                                     NSURLRequest *request) {
    return originalDataTaskRequest(self, _cmd, requestBySpoofingVersionHeader(request));
}

typedef NSURLSessionUploadTask *(*UploadTaskDataCompletionIMP)(NSURLSession *, SEL, NSURLRequest *, NSData *, void (^)(NSData *, NSURLResponse *, NSError *));
static UploadTaskDataCompletionIMP originalUploadTaskDataCompletion = NULL;

static NSURLSessionUploadTask *spoofedUploadTaskDataCompletion(NSURLSession *self,
                                                                SEL _cmd,
                                                                NSURLRequest *request,
                                                                NSData *bodyData,
                                                                void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    return originalUploadTaskDataCompletion(self, _cmd,
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
        reloadPreferences();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        preferencesChanged,
                                        (__bridge CFStringRef)kPreferencesChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        installBundleSpoofs();
        installNetworkSpoofs();

        NSLog(@"[OBDelevenUpdateBypass] v1.0.5 loaded; version=%@ build=%@ header=%@",
              currentSpoofedShortVersion(),
              kSpoofedBuildVersion,
              kMobileVersionHeader);
    }
}
