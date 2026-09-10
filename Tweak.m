#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <substrate.h>

/*
 * OBDeleven Update Bypass v1.0.4
 * Target: regular OBDeleven 1.11.0
 * Bundle: com.voltasit.obdeleven.ios.basic
 *
 * This version deliberately does NOT patch IntroPresenter, its enum state,
 * jump tables, or ForceUpdateViewController. Earlier builds proved that
 * forcing the ready path can skip startup work and leave the app sitting on
 * the static OBDeleven launch icon.
 *
 * Instead, 1.0.4 makes the old app report itself as a current release and then
 * lets OBDeleven's original startup/update state machine run normally.
 */

static NSString *const kSpoofedShortVersion = @"2.10.0";
/* High, but still safe for signed 32-bit code paths. */
static NSString *const kSpoofedBuildVersion = @"2147483647";
static NSString *const kMobileVersionHeader = @"x-mobile-app-version";
static NSBundle *gMainBundle = nil;

static BOOL isTargetBundle(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.voltasit.obdeleven.ios.basic"];
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

#pragma mark - Network version header spoof

static NSURLRequest *requestBySpoofingVersionHeader(NSURLRequest *request) {
    if (!request) return request;

    NSMutableURLRequest *mutable = [request mutableCopy];
    [mutable setValue:kSpoofedShortVersion forHTTPHeaderField:kMobileVersionHeader];
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
        installBundleSpoofs();
        installNetworkSpoofs();

        NSLog(@"[OBDelevenUpdateBypass] v1.0.4 loaded; version=%@ build=%@ header=%@",
              kSpoofedShortVersion,
              kSpoofedBuildVersion,
              kMobileVersionHeader);
    }
}
