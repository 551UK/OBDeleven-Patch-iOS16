#import "OBDUBRootListController.h"

#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

static NSString *const kPreferencesDomain = @"com.551.obdelevenupdatebypass";
static NSString *const kPreferencesChangedNotification =
    @"com.551.obdelevenupdatebypass/preferences.changed";

@implementation OBDUBRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)postPreferencesChangedNotification {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kPreferencesChangedNotification,
        NULL,
        NULL,
        true);
}

- (void)resetWorkingDefaults {
    CFStringRef domain = (__bridge CFStringRef)kPreferencesDomain;

    CFPreferencesSetAppValue(CFSTR("enabled"), kCFBooleanTrue, domain);
    CFPreferencesSetAppValue(CFSTR("spoofedVersion"), CFSTR("2.10.0"), domain);
    CFPreferencesSetAppValue(CFSTR("spoofedBuild"), CFSTR("2147483647"), domain);
    CFPreferencesAppSynchronize(domain);

    [self postPreferencesChangedNotification];
    [self reloadSpecifiers];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Defaults Restored"
                                            message:@"Spoofed Version is 2.10.0 and Spoofed Build is 2147483647. Fully close and reopen OBDeleven so its update check runs again."
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/OBDeleven-Patch-iOS16"];
    if (!url) return;

    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [application openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [application openURL:url];
#pragma clang diagnostic pop
    }
}

@end
