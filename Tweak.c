#include <substrate.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <string.h>

#define UPDATE_RESULT_OFFSET 0x155BE8UL
#define APP_USABILITY_SWITCH_ENTRY_OFFSET 0x15EB40UL

/*
 * OBDelevenUpdateBypass
 * Target: regular OBDeleven 1.11.0 (com.voltasit.obdeleven.ios.basic)
 * Rootless Dopamine / ElleKit.
 *
 * Patch 1: real version decision in ShouldUpdateApplicationUseCase.swift.
 *
 * Original @ main image + 0x155BE8:
 *   14 A5 88 9A    cinc x20, x8, lt
 *
 * Patched:
 *   F4 03 08 AA    mov x20, x8
 *
 * Patch 2: final AppUsabilityState dispatch used by IntroPresenter.
 * Swift metadata shows the no-payload states in this order:
 *   0 sessionTokenExpired
 *   1 appIsReadyToBeUsed
 *   2 appUpdateIsRequired
 *   3 userPasswordChangeIsRequired
 *
 * The state-2 jump-table entry leads to 0x10015E944. That branch resolves
 * ForceUpdateViewController and presents the full-screen "Update Required"
 * page. Redirect state 2 to the state-1 handler at 0x10015E908 instead.
 *
 * Jump table @ main image + 0x15EB38, entry for state 2 @ +0x15EB40:
 *   original:    40 01 00 00    relative target +0x140 -> 0x10015E944
 *   replacement: 04 01 00 00    relative target +0x104 -> 0x10015E908
 *
 * Both writes are protected by exact-byte checks for OBDeleven 1.11.0.
 */

static void patchIfMatches(uint8_t *target,
                           const uint8_t expected[4],
                           const uint8_t replacement[4]) {
    if (memcmp(target, expected, 4) == 0) {
        MSHookMemory(target, replacement, 4);
    }
}

__attribute__((constructor))
static void OBDelevenUpdateBypassInit(void) {
    const struct mach_header *mainHeader = _dyld_get_image_header(0);
    if (!mainHeader) return;

    uint8_t *base = (uint8_t *)mainHeader;

    const uint8_t updateExpected[4]    = { 0x14, 0xA5, 0x88, 0x9A };
    const uint8_t updateReplacement[4] = { 0xF4, 0x03, 0x08, 0xAA };
    patchIfMatches(base + UPDATE_RESULT_OFFSET,
                   updateExpected,
                   updateReplacement);

    const uint8_t stateExpected[4]    = { 0x40, 0x01, 0x00, 0x00 };
    const uint8_t stateReplacement[4] = { 0x04, 0x01, 0x00, 0x00 };
    patchIfMatches(base + APP_USABILITY_SWITCH_ENTRY_OFFSET,
                   stateExpected,
                   stateReplacement);
}
