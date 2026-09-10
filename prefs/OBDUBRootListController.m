#import "OBDUBRootListController.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#include <spawn.h>

extern char **environ;

static NSString *const kPreferencesDomain = @"com.551.obdelevenupdatebypass";
static NSString *const kPreferencesChangedNotification =
    @"com.551.obdelevenupdatebypass/preferences.changed";

static id CopyPreferenceValue(NSString *key) {
    if (key.length == 0) return nil;

    CFPreferencesAppSynchronize((__bridge CFStringRef)kPreferencesDomain);
    CFPropertyListRef raw = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPreferencesDomain);
    if (!raw) return nil;
    return CFBridgingRelease(raw);
}

static void SetPreferenceValue(NSString *key, id value) {
    if (key.length == 0) return;

    CFPreferencesSetAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)kPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPreferencesDomain);
}

static BOOL SpawnCommand(const char *path, char *const argv[]) {
    pid_t pid = 0;
    return posix_spawn(&pid, path, NULL, NULL, argv, environ) == 0;
}

@implementation OBDUBRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)postPreferencesChangedNotification {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPreferencesDomain);

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kPreferencesChangedNotification,
        NULL,
        NULL,
        true);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id value = CopyPreferenceValue(key);
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;

    SetPreferenceValue(key, value);
    [self postPreferencesChangedNotification];
}

- (void)resetWorkingDefaults {
    SetPreferenceValue(@"enabled", @YES);
    SetPreferenceValue(@"spoofedVersion", @"2.10.0");

    CFPreferencesSetAppValue(
        CFSTR("spoofedBuild"),
        NULL,
        (__bridge CFStringRef)kPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPreferencesDomain);

    [self postPreferencesChangedNotification];
    [self reloadSpecifiers];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Spoofed Version Reset"
                                            message:@"Spoofed Version is now 2.10.0. Fully close and reopen OBDeleven so its startup update check runs again."
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring {
    [self postPreferencesChangedNotification];

    char *sbreloadArgs[] = {(char *)"sbreload", NULL};
    if (SpawnCommand("/var/jb/usr/bin/sbreload", sbreloadArgs)) {
        return;
    }

    char *rootlessKillallArgs[] = {(char *)"killall", (char *)"-9", (char *)"SpringBoard", NULL};
    if (SpawnCommand("/var/jb/usr/bin/killall", rootlessKillallArgs)) {
        return;
    }

    char *systemKillallArgs[] = {(char *)"killall", (char *)"-9", (char *)"SpringBoard", NULL};
    SpawnCommand("/usr/bin/killall", systemKillallArgs);
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
