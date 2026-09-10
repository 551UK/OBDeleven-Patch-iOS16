// Declares the settings reader, writer, per-app reset buttons and navigation actions.
#import <Preferences/PSListController.h>

@class PSSpecifier;

@interface OBDUBRootListController : PSListController
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)resetWorkingDefaults;
- (void)resetVAGDefaults;
- (void)respring;
- (void)openGitHub;
@end
