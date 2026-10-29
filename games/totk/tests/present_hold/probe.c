// present_hold.h: the first frame of a pause (quick-select bar, inventory) comes with the world already gone and the
// game's still picture of it not drawn yet; the present shows the previous picture once instead of that black frame.
#include <stdio.h>
#include "present_hold.h"

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

int main(void) {
    check(present_hold(3627, 185), "a world frame, then the first pause frame (measured 3627 -> 185 draws): held");
    check(!present_hold(185, 394), "the second pause frame (the still picture is drawn again): shown");
    check(!present_hold(394, 390), "pause frames after it: shown");
    check(!present_hold(3617, 3627), "world frames: shown");
    check(!present_hold(390, 3600), "back to the world: shown");
    check(!present_hold(0, 185), "the very first frame (nothing to show instead): shown");
    check(present_hold(1500, 132), "a light world frame (the sky, 1500 draws), then the first pause frame: held");
    check(!present_hold(1500, 900), "a world frame that is just lighter than the one before: shown");
    check(!present_hold(900, 132), "fewer than 1000 draws before is no world frame: shown");
    printf("present_hold: %d checks, %d failures\n", checked, failures);
    return failures != 0;
}
