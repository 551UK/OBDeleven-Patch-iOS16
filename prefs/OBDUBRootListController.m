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

    CFPropertyListRef raw = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    if (!raw) return nil;
    return CFBridgingRelease(raw);
}

static void SetPreferenceValue(NSString *key, id value) {
    if (key.length == 0) return;

    CFPreferencesSetValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);

    CFPreferencesSynchronize(
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
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
    CFPreferencesSynchronize(
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);

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

    // Delete the old v1.0.5 build preference. v1.0.6 deliberately keeps the
    // proven high build spoof internally so one visible version field controls
    // the whole bypass and returning to 1.11.0 disables every spoof at once.
    CFPreferencesSetValue(
        CFSTR("spoofedBuild"),
        NULL,
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);
    CFPreferencesSynchronize(
        (__bridge CFStringRef)kPreferencesDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);

    [self postPreferencesChangedNotification];
    [self reloadSpecifiers];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Defaults Restored"
                                            message:@"Spoofed Version is back to 2.10.0. Fully close and reopen OBDeleven after changing the version so its startup update check runs again."
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
