// space_skip.h: Space is X in the world; in a cutscene or a dialog A and X together (A goes on and hurries the text, X
// skips); in the inventory, the Adventure Log and the title screen only A (X sorts the inventory).
#include <stdio.h>
#include "space_skip.h"

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

int main(void) {
    check(space_role(1, 0, 0) == SPACE_WORLD, "the world (its camera updating): X");
    check(space_role(0, 0, 0) == SPACE_SKIP, "a cutscene or a dialog (no camera action of the world): A and X");
    check(space_role(0, 0, 1) == SPACE_CONFIRM, "the inventory or the Adventure Log: A only");
    check(space_role(0, 1, 0) == SPACE_CONFIRM, "the title screen: A only");
    check(space_role(1, 0, 1) == SPACE_WORLD, "the world wins over a stale menu sign");
    printf("space_skip: %d checks, %d failures\n", checked, failures);
    return failures != 0;
}
