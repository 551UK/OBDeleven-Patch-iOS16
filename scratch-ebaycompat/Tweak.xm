#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <substrate.h>

static NSString *const EBTargetBundleID = @"com.ebay.iphone";
static NSString *const EBSpoofedVersion = @"6.272.0";
static NSString *const EBSpoofedBuild = @"2147483647";
static NSString *const EBSpoofedTransportOS = @"18.0";

static NSArray<NSString *> *EBOldVersions(void) {
    static NSArray<NSString *> *versions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        versions = @[@"6.96.0", @"6.267.0"];
    });
    return versions;
}

static BOOL EBIsKnownOldVersion(id value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    for (NSString *old in EBOldVersions()) {
        if ([(NSString *)value isEqualToString:old]) return YES;
    }
    return NO;
}

static BOOL EBShouldSpoofNSBundle(NSBundle *bundle) {
    if (!bundle) return NO;
    if (bundle == [NSBundle mainBundle]) return YES;

    NSString *identifier = [bundle bundleIdentifier];
    if ([identifier isEqualToString:EBTargetBundleID]) return YES;
    if ([identifier hasPrefix:@"com.ebay."] || [identifier hasPrefix:@"com.ebayent."]) return YES;
    return NO;
}

static BOOL EBShouldSpoofCFBundle(CFBundleRef bundle) {
    if (!bundle) return NO;
    if (bundle == CFBundleGetMainBundle()) return YES;

    CFStringRef ident = CFBundleGetIdentifier(bundle);
    if (!ident) return NO;
    NSString *identifier = (__bridge NSString *)ident;
    return [identifier isEqualToString:EBTargetBundleID] ||
           [identifier hasPrefix:@"com.ebay."] ||
           [identifier hasPrefix:@"com.ebayent."];
}

static NSString *EBReplaceOldVersions(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return value;

    NSString *result = value;
    for (NSString *old in EBOldVersions()) {
        result = [result stringByReplacingOccurrencesOfString:old withString:EBSpoofedVersion];
    }
    return result;
}

static NSString *EBTransportOSRewrite(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return value;

    NSString *actual = [[UIDevice currentDevice] systemVersion];
    if (actual.length == 0) return value;

    NSString *result = [value stringByReplacingOccurrencesOfString:actual
                                                         withString:EBSpoofedTransportOS];

    NSString *actualUnderscore = [actual stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *spoofUnderscore = [EBSpoofedTransportOS stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    result = [result stringByReplacingOccurrencesOfString:actualUnderscore
                                                withString:spoofUnderscore];
    return result;
}

static NSString *EBRewriteHeaderValue(NSString *value, NSString *field) {
    if (![value isKindOfClass:[NSString class]]) return value;

    NSString *lower = [field lowercaseString] ?: @"";
    if ([lower isEqualToString:@"x-ebay-mobile-app-version"]) {
        return EBSpoofedVersion;
    }

    NSString *result = EBReplaceOldVersions(value);

    // These fields describe the mobile app/device rather than an eBay API schema version.
    // Keep API version headers such as X-EBAY-C-VERSION untouched unless they literally
    // contain the old app version.
    if ([lower isEqualToString:@"user-agent"] ||
        [lower isEqualToString:@"x-ebay-mobile-app-info"] ||
        [lower containsString:@"app-version"] ||
        [lower containsString:@"client-version"]) {
        result = EBTransportOSRewrite(result);
    }

    if ([lower isEqualToString:@"x-ebay-mobile-app-info"] ||
        [lower isEqualToString:@"x-ebay-mobile-app-build"]) {
        result = [result stringByReplacingOccurrencesOfString:@"3839"
                                                    withString:EBSpoofedBuild];
    }

    return result;
}

static NSDictionary *EBRewriteHeaders(NSDictionary *headers) {
    if (![headers isKindOfClass:[NSDictionary class]] || headers.count == 0) return headers;

    NSMutableDictionary *copy = [headers mutableCopy];
    for (id rawKey in [headers allKeys]) {
        if (![rawKey isKindOfClass:[NSString class]]) continue;
        id rawValue = headers[rawKey];
        if (![rawValue isKindOfClass:[NSString class]]) continue;
        copy[rawKey] = EBRewriteHeaderValue(rawValue, rawKey);
    }
    return copy;
}

static BOOL EBIsLikelyEBayHost(NSString *host) {
    if (![host isKindOfClass:[NSString class]] || host.length == 0) return NO;
    return [[host lowercaseString] containsString:@"ebay"];
}

static NSURL *EBRewriteURL(NSURL *url) {
    if (!url || !EBIsLikelyEBayHost(url.host)) return url;

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) return url;

    BOOL changed = NO;
    NSArray<NSURLQueryItem *> *items = components.queryItems;
    if (items.count > 0) {
        NSMutableArray<NSURLQueryItem *> *rewritten = [NSMutableArray arrayWithCapacity:items.count];
        for (NSURLQueryItem *item in items) {
            NSString *name = item.name ?: @"";
            NSString *lower = [name lowercaseString];
            NSString *value = item.value;
            NSString *newValue = EBReplaceOldVersions(value);

            if ([lower isEqualToString:@"appversion"] ||
                [lower isEqualToString:@"app_version"] ||
                [lower isEqualToString:@"clientversion"] ||
                [lower isEqualToString:@"client_version"] ||
                [lower isEqualToString:@"mobile_app_version"]) {
                newValue = EBSpoofedVersion;
            } else if ([lower isEqualToString:@"buildnumber"] ||
                       [lower isEqualToString:@"build_number"] ||
                       [lower isEqualToString:@"appbuild"] ||
                       [lower isEqualToString:@"app_build"] ||
                       [lower isEqualToString:@"buildversion"] ||
                       [lower isEqualToString:@"build_version"]) {
                newValue = EBSpoofedBuild;
            } else if ([lower isEqualToString:@"osversion"] ||
                       [lower isEqualToString:@"os_version"] ||
                       [lower isEqualToString:@"iosversion"] ||
                       [lower isEqualToString:@"ios_version"]) {
                newValue = EBSpoofedTransportOS;
            }

            if ((value || newValue) && ![value isEqualToString:newValue]) changed = YES;
            [rewritten addObject:[NSURLQueryItem queryItemWithName:name value:newValue]];
        }
        if (changed) components.queryItems = rewritten;
    }

    // Also catch a literal version embedded in an eBay URL path/query that was not
    // represented as a normal query item.
    NSURL *candidate = changed ? components.URL : url;
    NSString *absolute = candidate.absoluteString;
    NSString *replaced = EBReplaceOldVersions(absolute);
    if (![absolute isEqualToString:replaced]) {
        NSURL *literalURL = [NSURL URLWithString:replaced];
        if (literalURL) candidate = literalURL;
    }
    return candidate;
}

static NSString *EBRewriteBodyString(NSString *body) {
    if (![body isKindOfClass:[NSString class]] || body.length == 0) return body;

    NSString *result = EBReplaceOldVersions(body);
    NSString *actualOS = [[UIDevice currentDevice] systemVersion] ?: @"";

    NSArray<NSArray<NSString *> *> *versionPairs = @[
        @[@"\"app_version\":\"6.96.0\"", [NSString stringWithFormat:@"\"app_version\":\"%@\"", EBSpoofedVersion]],
        @[@"\"app_version\":\"6.267.0\"", [NSString stringWithFormat:@"\"app_version\":\"%@\"", EBSpoofedVersion]],
        @[@"\"appVersion\":\"6.96.0\"", [NSString stringWithFormat:@"\"appVersion\":\"%@\"", EBSpoofedVersion]],
        @[@"\"appVersion\":\"6.267.0\"", [NSString stringWithFormat:@"\"appVersion\":\"%@\"", EBSpoofedVersion]],
        @[@"\"clientVersion\":\"6.96.0\"", [NSString stringWithFormat:@"\"clientVersion\":\"%@\"", EBSpoofedVersion]],
        @[@"\"clientVersion\":\"6.267.0\"", [NSString stringWithFormat:@"\"clientVersion\":\"%@\"", EBSpoofedVersion]],
        @[@"\"build_version\":\"3839\"", [NSString stringWithFormat:@"\"build_version\":\"%@\"", EBSpoofedBuild]],
        @[@"\"buildVersion\":\"3839\"", [NSString stringWithFormat:@"\"buildVersion\":\"%@\"", EBSpoofedBuild]],
        @[@"\"buildnumber\":\"3839\"", [NSString stringWithFormat:@"\"buildnumber\":\"%@\"", EBSpoofedBuild]]
    ];
    for (NSArray<NSString *> *pair in versionPairs) {
        result = [result stringByReplacingOccurrencesOfString:pair[0] withString:pair[1]];
    }

    if (actualOS.length > 0) {
        NSArray<NSString *> *osKeys = @[@"os_version", @"osVersion", @"ios_version", @"iosVersion"];
        for (NSString *key in osKeys) {
            NSString *from = [NSString stringWithFormat:@"\"%@\":\"%@\"", key, actualOS];
            NSString *to = [NSString stringWithFormat:@"\"%@\":\"%@\"", key, EBSpoofedTransportOS];
            result = [result stringByReplacingOccurrencesOfString:from withString:to];
        }
    }
    return result;
}

static NSData *EBRewriteBody(NSData *body, NSURL *url) {
    if (!body || body.length == 0 || body.length > (2 * 1024 * 1024)) return body;
    if (!EBIsLikelyEBayHost(url.host)) return body;

    NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if (!text) return body;

    NSString *rewritten = EBRewriteBodyString(text);
    if ([rewritten isEqualToString:text]) return body;
    return [rewritten dataUsingEncoding:NSUTF8StringEncoding] ?: body;
}

static NSURLRequest *EBRewriteRequest(NSURLRequest *request) {
    if (!request) return request;

    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    if (!mutableRequest) return request;

    NSURL *newURL = EBRewriteURL(mutableRequest.URL);
    if (newURL && ![newURL isEqual:mutableRequest.URL]) mutableRequest.URL = newURL;

    NSDictionary *headers = EBRewriteHeaders(mutableRequest.allHTTPHeaderFields);
    if (headers) mutableRequest.allHTTPHeaderFields = headers;

    NSData *body = mutableRequest.HTTPBody;
    NSData *rewrittenBody = EBRewriteBody(body, mutableRequest.URL);
    if (rewrittenBody && rewrittenBody != body && ![rewrittenBody isEqualToData:body]) {
        mutableRequest.HTTPBody = rewrittenBody;
        [mutableRequest setValue:[NSString stringWithFormat:@"%lu", (unsigned long)rewrittenBody.length]
       forHTTPHeaderField:@"Content-Length"];
    }

    return mutableRequest;
}

#pragma mark - CFBundle version path

typedef CFTypeRef (*CFBundleGetValueIMP)(CFBundleRef bundle, CFStringRef key);
static CFBundleGetValueIMP originalCFBundleGetValue = NULL;

static CFTypeRef EB_CFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key) {
    if (bundle && key && EBShouldSpoofCFBundle(bundle)) {
        if (CFEqual(key, CFSTR("CFBundleShortVersionString"))) {
            return (__bridge CFTypeRef)EBSpoofedVersion;
        }
        if (CFEqual(key, CFSTR("CFBundleVersion"))) {
            return (__bridge CFTypeRef)EBSpoofedBuild;
        }
    }
    return originalCFBundleGetValue(bundle, key);
}

%hook NSBundle

- (id)objectForInfoDictionaryKey:(NSString *)key {
    id original = %orig;
    if (!EBShouldSpoofNSBundle(self)) return original;

    if ([key isEqualToString:@"CFBundleShortVersionString"] &&
        (EBIsKnownOldVersion(original) || self == [NSBundle mainBundle])) {
        return EBSpoofedVersion;
    }
    if ([key isEqualToString:@"CFBundleVersion"] &&
        (([original isKindOfClass:[NSString class]] && [original isEqualToString:@"3839"]) ||
         self == [NSBundle mainBundle])) {
        return EBSpoofedBuild;
    }
    return original;
}

- (NSDictionary *)infoDictionary {
    NSDictionary *original = %orig;
    if (!original || !EBShouldSpoofNSBundle(self)) return original;

    id shortVersion = original[@"CFBundleShortVersionString"];
    id build = original[@"CFBundleVersion"];
    BOOL versionMatch = EBIsKnownOldVersion(shortVersion) || self == [NSBundle mainBundle];
    BOOL buildMatch = ([build isKindOfClass:[NSString class]] && [build isEqualToString:@"3839"]) || self == [NSBundle mainBundle];
    if (!versionMatch && !buildMatch) return original;

    NSMutableDictionary *copy = [original mutableCopy];
    if (versionMatch) copy[@"CFBundleShortVersionString"] = EBSpoofedVersion;
    if (buildMatch) copy[@"CFBundleVersion"] = EBSpoofedBuild;
    return copy;
}

%end

#pragma mark - Header construction paths

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig(EBRewriteHeaderValue(value, field), field);
}

- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig(EBRewriteHeaderValue(value, field), field);
}

- (void)setAllHTTPHeaderFields:(NSDictionary<NSString *, NSString *> *)headerFields {
    %orig(EBRewriteHeaders(headerFields));
}

%end

#pragma mark - NSURLSession default-header path

%hook NSURLSessionConfiguration

- (void)setHTTPAdditionalHeaders:(NSDictionary *)headers {
    %orig(EBRewriteHeaders(headers));
}

%end

#pragma mark - NSURLSession send paths

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    return %orig(EBRewriteRequest(request), completionHandler);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(EBRewriteRequest(request));
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *rewritten = EBRewriteRequest(request);
    NSData *body = EBRewriteBody(bodyData, rewritten.URL);
    return %orig(rewritten, body, completionHandler);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData {
    NSURLRequest *rewritten = EBRewriteRequest(request);
    NSData *body = EBRewriteBody(bodyData, rewritten.URL);
    return %orig(rewritten, body);
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    return %orig(EBRewriteRequest(request), completionHandler);
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    return %orig(EBRewriteRequest(request));
}

%end

#pragma mark - Legacy networking used by older eBay modules

%hook NSURLConnection

- (instancetype)initWithRequest:(NSURLRequest *)request
                       delegate:(id)delegate
               startImmediately:(BOOL)startImmediately {
    return %orig(EBRewriteRequest(request), delegate, startImmediately);
}

+ (void)sendAsynchronousRequest:(NSURLRequest *)request
                          queue:(NSOperationQueue *)queue
              completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))handler {
    %orig(EBRewriteRequest(request), queue, handler);
}

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error {
    return %orig(EBRewriteRequest(request), response, error);
}

%end

#pragma mark - Web-backed eBay screens

%hook WKWebViewConfiguration

- (void)setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent {
    NSString *rewritten = EBTransportOSRewrite(EBReplaceOldVersions(applicationNameForUserAgent));
    %orig(rewritten);
}

%end

%hook WKWebView

- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    return %orig(EBRewriteRequest(request));
}

- (void)setCustomUserAgent:(NSString *)customUserAgent {
    NSString *rewritten = EBTransportOSRewrite(EBReplaceOldVersions(customUserAgent));
    %orig(rewritten);
}

%end

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:EBTargetBundleID]) return;

        MSHookFunction((void *)CFBundleGetValueForInfoDictionaryKey,
                       (void *)EB_CFBundleGetValueForInfoDictionaryKey,
                       (void **)&originalCFBundleGetValue);

        NSLog(@"[eBayCompat14] loaded: runtime app spoof=%@ build=%@ transportOS=%@",
              EBSpoofedVersion, EBSpoofedBuild, EBSpoofedTransportOS);
    }
}
