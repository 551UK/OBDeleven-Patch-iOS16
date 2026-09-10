#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <substrate.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <string.h>

#define UPDATE_RESULT_OFFSET 0x155BE8UL
#define APP_USABILITY_STATE_LOAD_OFFSET 0x15E778UL
#define APP_USABILITY_SWITCH_ENTRY_OFFSET 0x15EB40UL

static void patchIfMatches(uint8_t *target,
                           const uint8_t expected[4],
                           const uint8_t replacement[4]) {
    if (memcmp(target, expected, 4) == 0) {
        MSHookMemory(target, replacement, 4);
    }
}

static BOOL classNameContainsForceUpdate(Class cls) {
    while (cls) {
        const char *name = class_getName(cls);
        if (name && strstr(name, "ForceUpdateViewController")) {
            return YES;
        }
        cls = class_getSuperclass(cls);
    }
    return NO;
}

static BOOL isForceUpdateController(UIViewController *controller) {
    if (!controller) return NO;

    if (classNameContainsForceUpdate(object_getClass(controller))) {
        return YES;
    }

    if ([controller isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)controller;
        if (isForceUpdateController(nav.topViewController)) return YES;
        if (isForceUpdateController(nav.visibleViewController)) return YES;
    }

    return NO;
}

typedef void (*PresentViewControllerIMP)(id, SEL, UIViewController *, BOOL, id);
static PresentViewControllerIMP originalPresentViewController = NULL;

static void bypassPresentViewController(id self,
                                        SEL _cmd,
                                        UIViewController *controller,
                                        BOOL animated,
                                        id completion) {
    if (isForceUpdateController(controller)) {
        NSLog(@"[OBDelevenUpdateBypass] blocked ForceUpdateViewController presentation");
        return;
    }

    originalPresentViewController(self, _cmd, controller, animated, completion);
}

typedef void (*PushViewControllerIMP)(id, SEL, UIViewController *, BOOL);
static PushViewControllerIMP originalPushViewController = NULL;

static void bypassPushViewController(id self,
                                     SEL _cmd,
                                     UIViewController *controller,
                                     BOOL animated) {
    if (isForceUpdateController(controller)) {
        NSLog(@"[OBDelevenUpdateBypass] blocked ForceUpdateViewController push");
        return;
    }

    originalPushViewController(self, _cmd, controller, animated);
}

static void installPresentationFailsafes(void) {
    Class viewControllerClass = objc_getClass("UIViewController");
    SEL presentSelector = sel_registerName("presentViewController:animated:completion:");
    if (viewControllerClass && class_getInstanceMethod(viewControllerClass, presentSelector)) {
        MSHookMessageEx(viewControllerClass,
                        presentSelector,
                        (IMP)bypassPresentViewController,
                        (IMP *)&originalPresentViewController);
    }

    Class navigationControllerClass = objc_getClass("UINavigationController");
    SEL pushSelector = sel_registerName("pushViewController:animated:");
    if (navigationControllerClass && class_getInstanceMethod(navigationControllerClass, pushSelector)) {
        MSHookMessageEx(navigationControllerClass,
                        pushSelector,
                        (IMP)bypassPushViewController,
                        (IMP *)&originalPushViewController);
    }
}

__attribute__((constructor))
static void OBDelevenUpdateBypassInit(void) {
    const struct mach_header *mainHeader = _dyld_get_image_header(0);
    if (!mainHeader) return;

    uint8_t *base = (uint8_t *)mainHeader;

    /*
     * Patch 1: ShouldUpdateApplicationUseCase.swift
     *
     * Original @ +0x155BE8:
     *   14 A5 88 9A    cinc x20, x8, lt
     *
     * Patched:
     *   F4 03 08 AA    mov  x20, x8
     */
    const uint8_t updateExpected[4]    = { 0x14, 0xA5, 0x88, 0x9A };
    const uint8_t updateReplacement[4] = { 0xF4, 0x03, 0x08, 0xAA };
    patchIfMatches(base + UPDATE_RESULT_OFFSET,
                   updateExpected,
                   updateReplacement);

    /*
     * Patch 2: IntroPresenter.startUsabilityStateCheck()
     *
     * The async result is loaded here directly into x23 before the app
     * compares the state and dispatches through the AppUsabilityState
     * jump table.
     *
     * Original @ +0x15E778:
     *   D7 4E 40 F9    ldr x23, [x22, #0x98]
     *
     * Patched:
     *   37 00 80 D2    mov x23, #1
     *
     * State 1 is appIsReadyToBeUsed, while state 2 is appUpdateIsRequired.
     */
    const uint8_t stateLoadExpected[4]    = { 0xD7, 0x4E, 0x40, 0xF9 };
    const uint8_t stateLoadReplacement[4] = { 0x37, 0x00, 0x80, 0xD2 };
    patchIfMatches(base + APP_USABILITY_STATE_LOAD_OFFSET,
                   stateLoadExpected,
                   stateLoadReplacement);

    /*
     * Patch 3: retain the v1.0.1 jump-table redirect as a second binary
     * failsafe. State 2 is redirected to the state-1 handler.
     */
    const uint8_t stateExpected[4]    = { 0x40, 0x01, 0x00, 0x00 };
    const uint8_t stateReplacement[4] = { 0x04, 0x01, 0x00, 0x00 };
    patchIfMatches(base + APP_USABILITY_SWITCH_ENTRY_OFFSET,
                   stateExpected,
                   stateReplacement);

    /*
     * Final failsafe: this exact launch path presents ForceUpdateViewController
     * via -presentViewController:animated:completion:. Block that controller
     * (and any navigation push of it) by class name.
     */
    installPresentationFailsafes();

    NSLog(@"[OBDelevenUpdateBypass] v1.0.2 loaded");
}
