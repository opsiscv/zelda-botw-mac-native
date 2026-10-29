// runtime/menu_pointer.h: the title menu under the mouse, and the cursor's item from its corner pane.
#include <stdio.h>
#include "menu_pointer.h"
static int menu_title_item5(double w, double h, double x, double y) { return menu_title_item(w, h, x, y, 5); }

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

int main(void) {
    /* a 1920x1080 view: the 1280x720 layout scaled 1.5; Continue's line is the middle row (y 540 from the bottom) */
    check(menu_title_item5(1920, 1080, 1770, 540) == 0, "Continue under the mouse");
    check(menu_title_item5(1920, 1080, 1770, 540 - 60) == 1, "New Game one line (40 layout units) below");
    check(menu_title_item5(1920, 1080, 1700, 540 - 240) == 4, "Downloadable Content, the fifth");
    check(menu_title_item5(1920, 1080, 600, 540) < 0, "the left side of the screen is no item");
    check(menu_title_item5(1920, 1080, 1770, 540 - 330) < 0, "below the last item is none");
    check(menu_title_item5(1920, 1200, 1770, 600) == 0, "a taller view: the picture is centred, bars above and below");
    check(menu_title_item5(1920, 1080, 1600, 540) < 0, "left of Continue's text is not Continue (the boxes hug the text)");
    check(menu_title_item5(1920, 1080, 1600, 540 - 240) == 4, "but Downloadable Content is that long");
    check(menu_title_item5(1920, 1080, 1770, 540 - 30) < 0, "between two lines is neither");
    check(menu_title_item5(1920, 1080, 1890, 540) < 0, "right of the text is none");
    int cnt = 0;
    check(menu_title_index(981, 10, &cnt) == 0 && cnt == 5 && menu_title_index(981, -150, &cnt) == 4, "the cursor corner's height gives the item (5 items)");
    check(menu_title_index(981, -12, &cnt) < 0 && menu_title_index(500, 10, &cnt) < 0, "a corner off the title grid is not the title cursor");
    check(menu_title_index(981, 30, &cnt) == 0 && cnt == 6 && menu_title_index(981, -170, &cnt) == 5, "with the DLC: 6 items (Play in Master Mode), the list 20 units higher");
    check(menu_title_item(1920, 1080, 1770, 540 + 20 * 1.5, 6) == 0, "6 items: Continue's line is 20 units up");
    check(menu_title_item(1920, 1080, 1600, 540 - 60 * 1.5, 6) == 2, "Play in Master Mode is long");
    check(menu_title_item(1920, 1080, 1600, 540 - 100 * 1.5, 6) < 0, "Options is short");
    /* the load list's frame on its first save (layout units, y up): left -244, top 233, right 244, bottom 143 */
    const float fr[4] = { -244, 233, 244, 143 };
    int inside = 0;
    check(menu_frame_step(1920, 1080, 960, 540 + 188 * 1.5, fr, &inside) == 0 && inside, "the pointer on the selected save: no step, inside");
    check(menu_frame_step(1920, 1080, 960, 540 + 45 * 1.5, fr, &inside) == MENU_DOWN && !inside, "on a save below: a step down");
    check(menu_frame_step(1920, 1080, 960, 540 + 300 * 1.5, fr, &inside) == MENU_UP, "above the frame: a step up");
    check(menu_frame_step(1920, 1080, 960 + 400 * 1.5, 540 + 45 * 1.5, fr, &inside) == 0 && !inside, "far right of the list: nothing (no left / right steps: they change options)");
    check(menu_frame_step(1920, 1080, 960, 540 + 237 * 1.5, fr, &inside) == 0, "in the 4-unit margin just above: nothing yet");
    check(!menu_frame_valid(981, 10, 1001, -10), "the title's arrow corners are not a frame");
    check(menu_frame_valid(-244, 233, 244, 143), "the save frame is");

    const float cell[4] = { -400, 200, -320, 120 };   /* an inventory cell, 80 units */
    check(menu_frame_step(1920, 1080, 960 + (-200) * 1.5, 540 + 160 * 1.5, cell, &inside) == MENU_RIGHT, "a small frame (a grid cell): the pointer to its right on the same row steps right");
    check(menu_frame_step(1920, 1080, 960 + (-500) * 1.5, 540 + 160 * 1.5, cell, &inside) == MENU_LEFT, "and left");
    check(menu_frame_step(1920, 1080, 960 + (-200) * 1.5, 540 + 50 * 1.5, cell, &inside) == MENU_DOWN, "a cell further down and right: down first");
    check(menu_frame_step(1920, 1080, 960 + 400 * 1.5, 540 + 188 * 1.5, fr, &inside) == 0, "a wide frame (a list row) still never steps sideways");
    check(menu_frame_small(cell) && !menu_frame_small(fr), "small: a grid cell, not a list row");
    check(menu_frame_shown(0xff) && menu_frame_shown(0x80), "the frame drawn (a menu open, also the same item as last time): a menu");
    check(!menu_frame_shown(0x0a) && !menu_frame_shown(0), "faded out once its menu closed (the world, a cutscene): not a menu");

    MenuSteps m = {0};
    menu_steps_move(&m, 30, 0); check(menu_steps_next(&m) == 0, "less than a step of movement: nothing yet");
    menu_steps_move(&m, 15, 3); check(menu_steps_next(&m) == MENU_RIGHT, "past a step to the right: one step right");
    check(menu_steps_next(&m) == 0, "and only one");
    menu_steps_move(&m, 2, 130); check(menu_steps_next(&m) == MENU_DOWN && menu_steps_next(&m) == MENU_DOWN && menu_steps_next(&m) == MENU_DOWN && menu_steps_next(&m) == 0, "a long move down: a step per MENU_STEP_POINTS, mouse down is down");
    menu_steps_move(&m, -20, -50); check(menu_steps_next(&m) == MENU_UP, "up wins over a smaller sideways move");
    menu_steps_move(&m, 0, 30); menu_steps_reset(&m); menu_steps_move(&m, 0, 20); check(menu_steps_next(&m) == 0, "reset drops what was left");

    MenuWheel wh = {0};
    check(menu_wheel(&wh, 10.00, -0.1) == 1, "the first event of a notch is one step at once (down = +1), however small");
    check(menu_wheel(&wh, 10.01, -0.1) == 0 && menu_wheel(&wh, 10.02, -0.1) == 0, "the rest of that notch's events: nothing more");
    check(menu_wheel(&wh, 10.30, 0.2) == -1, "the next notch, after a pause, the other way: one step back");
    int n = 0; for (int i = 0; i < 10; i++) n += menu_wheel(&wh, 11.0 + 0.01 * i, -1.0);
    check(n >= 9 && n <= 10, "a fast spin (a line per event): a step per line");

    printf("menu-pointer: %d/%d checks pass\n", checked - failures, checked);
    return failures != 0;
}
