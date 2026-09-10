#include <substrate.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <string.h>

#define UPDATE_RESULT_OFFSET 0x155BE8UL

/*
 * OBDelevenUpdateBypass
 * Target: regular OBDeleven 1.11.0 (com.voltasit.obdeleven.ios.basic)
 * Rootless Dopamine / ElleKit.
 *
 * Reverse engineered update check in ShouldUpdateApplicationUseCase.swift:
 * the app compares the installed CFBundleVersion with the required version.
 *
 * Original @ main image + 0x155BE8:
 *   14 A5 88 9A    cinc x20, x8, lt
 *
 * When current < required this instruction changes the result to the
 * forced-update state. Replacing it with MOV keeps the same result used
 * when the installed version already satisfies the required version.
 *
 * Patched:
 *   F4 03 08 AA    mov x20, x8
 */

__attribute__((constructor))
static void OBDelevenUpdateBypassInit(void) {
    const struct mach_header *mainHeader = _dyld_get_image_header(0);
    if (!mainHeader) return;

    uint8_t *target = (uint8_t *)mainHeader + UPDATE_RESULT_OFFSET;
    const uint8_t expected[4]    = { 0x14, 0xA5, 0x88, 0x9A };
    const uint8_t replacement[4] = { 0xF4, 0x03, 0x08, 0xAA };

    /* Do not patch a different OBDeleven build by accident. */
    if (memcmp(target, expected, sizeof(expected)) != 0) return;

    MSHookMemory(target, replacement, sizeof(replacement));
}
