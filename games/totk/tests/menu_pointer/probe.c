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
    check(!menu_frame_valid(981, 10, 1001, -10), "the title's arrow corners are not a frame");
    check(menu_frame_valid(-244, 233, 244, 143), "the save frame is");

    const float cell[4] = { -400, 200, -320, 120 };   /* an inventory cell, 80 units */
    check(menu_frame_small(cell) && !menu_frame_small(fr), "small: a grid cell, not a list row");
    check(menu_frame_shown(0xff) && menu_frame_shown(0x80), "the frame drawn (a menu open, also the same item as last time): a menu");
    check(!menu_frame_shown(0x0a) && !menu_frame_shown(0), "faded out once its menu closed (the world, a cutscene): not a menu");

    MenuWheel wh = {0};
    check(menu_wheel(&wh, 10.00, -0.1) == 1, "the first event of a notch is one step at once (down = +1), however small");
    check(menu_wheel(&wh, 10.01, -0.1) == 0 && menu_wheel(&wh, 10.02, -0.1) == 0, "the rest of that notch's events: nothing more");
    check(menu_wheel(&wh, 10.30, 0.2) == -1, "the next notch, after a pause, the other way: one step back");
    int n = 0; for (int i = 0; i < 10; i++) n += menu_wheel(&wh, 11.0 + 0.01 * i, -1.0);
    check(n >= 9 && n <= 10, "a fast spin (a line per event): a step per line");

    /* Who has the mouse (menu_pointer_mode): the window only in the world; anywhere else the pointer is free. */
    check(menu_pointer_mode(1, -1, 0, 1) == MENU_POINTER_HELD, "the world: the mouse turns the camera");
    check(menu_pointer_mode(1, 2, 0, 0) == MENU_POINTER_TITLE, "the title menu");
    check(menu_pointer_mode(1, -1, 1, 0) == MENU_POINTER_FRAME, "a menu with a selection frame");
    check(menu_pointer_mode(1, -1, 0, 0) == MENU_POINTER_FREE, "the map, a dialog, a cutscene: the pointer, free");
    check(menu_pointer_mode(0, -1, 0, 0) == MENU_POINTER_OFF, "mouse mode off: the system's pointer");
    check(menu_pointer_mode(1, -1, 1, 1) == MENU_POINTER_FRAME, "a frame while the camera still updates (a dialog's choices): the frame");

    printf("menu-pointer: %d/%d checks pass\n", checked - failures, checked);
    return failures != 0;
}
