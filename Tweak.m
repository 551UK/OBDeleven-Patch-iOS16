#include <substrate.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <string.h>

#define FORCE_UPDATE_BRANCH_OFFSET 0x15E944UL

/*
 * OBDeleven Update Bypass v1.0.3
 * Target: regular OBDeleven 1.11.0
 * Bundle: com.voltasit.obdeleven.ios.basic
 *
 * This version deliberately patches only the final force-update branch.
 * The async usability check and all startup/setup work run normally.
 *
 * At +0x15E944 the app has already selected appUpdateIsRequired and is
 * entering the branch that constructs ForceUpdateViewController.
 * Redirect that branch to the existing appIsReadyToBeUsed handler at
 * +0x15E908.
 *
 * Original @ +0x15E944:
 *   D3 42 00 91    add x19, x22, #0x10
 *
 * Replacement:
 *   F1 FF FF 17    b   0x10015E908
 *
 * Delta = -0x3c bytes from 0x10015E944 to 0x10015E908.
 */

__attribute__((constructor))
static void OBDelevenUpdateBypassInit(void) {
    const struct mach_header *header = _dyld_get_image_header(0);
    if (!header) return;

    uint8_t *target = (uint8_t *)header + FORCE_UPDATE_BRANCH_OFFSET;
    const uint8_t expected[4]    = { 0xD3, 0x42, 0x00, 0x91 };
    const uint8_t replacement[4] = { 0xF1, 0xFF, 0xFF, 0x17 };

    /* Exact-build guard: do not patch an unknown OBDeleven executable. */
    if (memcmp(target, expected, sizeof(expected)) != 0) return;

    MSHookMemory(target, replacement, sizeof(replacement));
}
