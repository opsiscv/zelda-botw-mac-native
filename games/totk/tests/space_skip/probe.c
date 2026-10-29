// space_skip.h: Space skips (X and + together) in a cutscene, confirms (A) in a menu, stays X in the world.
#include <stdio.h>
#include "space_skip.h"

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

int main(void) {
    check(space_role(1, 0, 3600) == SPACE_WORLD, "the world (its camera updating): X");
    check(space_role(0, 0, 3600) == SPACE_SKIP, "a cutscene (the world drawn, no camera action of it): X and +");
    check(space_role(0, 0, 1000) == SPACE_SKIP, "a light cutscene (1000 draws): skip");
    check(space_role(0, 0, 390) == SPACE_CONFIRM, "the pause menu (the still picture, a few hundred draws): A");
    check(space_role(0, 1, 3600) == SPACE_CONFIRM, "the title screen: A");
    printf("space_skip: %d checks, %d failures\n", checked, failures);
    return failures != 0;
}
