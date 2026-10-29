// runtime/menu_grid.h: the inventory page as the game shows it (each slot: where it is, whether it holds an item), and
// any menu's hit boxes: the one under the pointer, the d-pad step toward it.
#include <stdio.h>
#include "menu_grid.h"

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

/* a weapons page: 5 columns x 4 rows, numbered by column (as Pa_Btn_00..19), items in row 0 (5) and row 1 (3) */
static int page(MenuSlot s[20]) {
    for (int i = 0; i < 20; i++) {
        int col = i / 4, row = i % 4;
        s[i] = (MenuSlot){ -476 + 98.0f * col, 97 - 98.0f * row, (row == 0) || (row == 1 && col < 3) };
    }
    return 20;
}
static int at(const MenuSlot *s, int n, int col, int row) { for (int i = 0; i < n; i++) if (s[i].x == -476 + 98.0f * col && s[i].y == 97 - 98.0f * row) return i; return -1; }

int main(void) {
    MenuSlot s[20]; page(s);
    MenuSlot part[20]; int pn = 0;
    for (int i = 1; i < 20; i++) part[pn++] = s[i];   /* the page's first slot is kept apart by the game */
    pn = menu_slots_complete(part, pn, 20);
    check(pn == 20 && at(part, pn, 0, 0) >= 0 && part[at(part, pn, 0, 0)].item, "a missing slot of the 5 x 4 page is put back, the first one holding an item when the page has any");
    MenuSlot none[20] = { { -378, 97, 0 }, { -280, 97, 0 }, { -182, 97, 0 } };   /* room for the put-back slots */
    int nn = menu_slots_complete(none, 3, 20);
    check(nn == 20 && at(none, nn, 0, 0) >= 0 && !none[at(none, nn, 0, 0)].item, "an empty page: the put-back slots hold nothing");

    /* Any menu with the cursor's element list (menu_hit_*): each element's hit box (B_Hit_00), the one under the
       pointer, and the d-pad step from the selected one toward it. */
    {
        MenuHit h[4] = { { -260, -30, 430, 64, 0 }, { -260, -100, 430, 64, 0 }, { -260, -170, 430, 64, 0 }, { -289, 191, 32, 32, 0 } };
        check(menu_hit_at(h, 4, -100, -95) == 1, "the pointer on the second quest");
        check(menu_hit_at(h, 4, -100, -65) < 0, "between two rows: nothing");
        check(menu_hit_at(h, 4, 100, -95) < 0, "right of the list: nothing");
        check(menu_hit_step(h, 0, 2) == MENU_DOWN, "a row further down: down");
        check(menu_hit_step(h, 2, 0) == MENU_UP, "back up: up");
        MenuHit g[2] = { { -476, 97, 90, 90, 0 }, { -378, -1, 90, 90, 0 } };
        check(menu_hit_step(g, 0, 1) == MENU_DOWN || menu_hit_step(g, 0, 1) == MENU_RIGHT, "a diagonal: one of its two ways");
        MenuHit r[2] = { { -476, 97, 90, 90, 0 }, { -280, 97, 90, 90, 0 } };
        check(menu_hit_step(r, 1, 0) == MENU_LEFT, "to the left: left");
        MenuHit o[2] = { { -260, 130, 486, 60, 0 }, { -280, 130, 32, 32, 0 } };
        check(menu_hit_at(o, 2, -280, 130) == 1, "a tab icon over a half-scrolled row: the smaller box");
    }

    printf("menu-grid: %d/%d checks pass\n", checked - failures, checked);
    return failures != 0;
}
