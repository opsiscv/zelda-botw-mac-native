// runtime/menu_grid.h: the inventory page as the game shows it (each slot: where it is, whether it holds an item), the
// slot under the mouse, and the shortest d-pad path to it over items only.
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
    MenuSlot s[20]; int n = page(s), path[32];
    check(menu_slot_at(s, n, -476, 97) == at(s, n, 0, 0), "the pointer on a slot's middle: that slot");
    check(menu_slot_at(s, n, -476 + 44, 97 - 44) == at(s, n, 0, 0), "anywhere on its 90 x 90 square");
    check(menu_slot_at(s, n, -476 + 49, 97) < 0, "in the gap between two slots: none");
    check(menu_slot_at(s, n, -280, -99) < 0, "on an empty slot: none (nothing to pick)");
    check(menu_slot_at(s, n, 60, 97) < 0 && menu_slot_at(s, n, -476, -400) < 0, "off the grid: none");
    int k = menu_slot_path(s, n, at(s, n, 0, 0), at(s, n, 2, 1), path, 32);
    check(k == 3, "row 0 col 0 to row 1 col 2: three steps");
    int r = 0, c = 0, ok = 1;
    for (int i = 0; i < k; i++) { if (path[i] == MENU_RIGHT) c++; else if (path[i] == MENU_LEFT) c--; else if (path[i] == MENU_DOWN) r++; else r--; if (at(s, n, c, r) < 0 || !s[at(s, n, c, r)].item) ok = 0; }
    check(ok && r == 1 && c == 2, "every step lands on an item, and it ends there");
    k = menu_slot_path(s, n, at(s, n, 4, 0), at(s, n, 1, 1), path, 32);
    r = 0; c = 4; ok = 1;
    for (int i = 0; i < k; i++) { if (path[i] == MENU_RIGHT) c++; else if (path[i] == MENU_LEFT) c--; else if (path[i] == MENU_DOWN) r++; else r--; if (at(s, n, c, r) < 0 || !s[at(s, n, c, r)].item) ok = 0; }
    check(ok && r == 1 && c == 1 && k == 4, "from the far end of row 0 to row 1: around, never through an empty slot (left then down)");
    check(menu_slot_path(s, n, at(s, n, 0, 0), at(s, n, 0, 0), path, 32) == 0, "already there: nothing");
    MenuSlot lone[2] = { { -476, 97, 1 }, { -280, 97, 1 } };
    check(menu_slot_path(lone, 2, 0, 1, path, 32) < 0, "no way over items (a gap): no path, nothing sent");
    MenuSlot part[20]; int pn = 0;
    for (int i = 1; i < 20; i++) part[pn++] = s[i];   /* the page's first slot is kept apart by the game */
    pn = menu_slots_complete(part, pn, 20);
    check(pn == 20 && menu_slot_at(part, pn, -476, 97) >= 0, "a missing slot of the 5 x 4 page is put back, the first one holding an item when the page has any");
    MenuSlot none[3] = { { -378, 97, 0 }, { -280, 97, 0 }, { -182, 97, 0 } };
    int nn = menu_slots_complete(none, 3, 20);
    check(nn == 20 && menu_slot_at(none, nn, -476, 97) < 0, "an empty page: the put-back slots hold nothing");

    printf("menu-grid: %d/%d checks pass\n", checked - failures, checked);
    return failures != 0;
}
