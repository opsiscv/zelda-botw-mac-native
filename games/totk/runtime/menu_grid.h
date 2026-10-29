/* Breath of the Wild's menus under the mouse. The inventory page as the game shows it (game_patches_botw.c
   runtime_inventory_slots, for the pause menu's tab signs): each slot's place and whether it holds an item. Any menu
   with the cursor's element list: each element's hit box (MenuHit), the one under the pointer, the d-pad step toward
   it. Layout units (1280 x 720, centre 0,0, y up). Plain C: tests/menu_grid/probe.c. */
#pragma once
#include <math.h>
#include <stdint.h>
#include "menu_pointer.h"

#define MENU_SLOT_STEP 98.0   /* from one slot to the next, either way */
#define MENU_GRID_PAGE_LEFT_X -530.0   /* the page on screen: its slots' centres lie between these (the next pages lie further right) */
#define MENU_GRID_PAGE_RIGHT_X -30.0
enum { MENU_SLOTS_MAX = 64 };

typedef struct { float x, y; int item; } MenuSlot;   /* a slot's centre, and whether it holds an item */

/* The page is a grid of MENU_GRID_COLS x MENU_GRID_ROWS slots from (MENU_GRID_X0, MENU_GRID_Y0); a slot the game keeps
   apart from the list (its first) is put back where it belongs, holding an item when the page holds any (items fill
   the page from its first slot). Returns the new count (out has room for max). */
#define MENU_GRID_X0 -476.0
#define MENU_GRID_Y0 97.0
enum { MENU_GRID_COLS = 5, MENU_GRID_ROWS = 4 };
static inline int menu_slots_complete(MenuSlot *s, int n, int max) {
    int any = 0;
    for (int i = 0; i < n; i++) any |= s[i].item;
    for (int c = 0; c < MENU_GRID_COLS; c++) for (int r = 0; r < MENU_GRID_ROWS; r++) {
        float x = (float)(MENU_GRID_X0 + MENU_SLOT_STEP * c), y = (float)(MENU_GRID_Y0 - MENU_SLOT_STEP * r); int found = 0;
        for (int i = 0; i < n; i++) if (fabsf(s[i].x - x) < 2 && fabsf(s[i].y - y) < 2) found = 1;
        if (!found && n < max) s[n++] = (MenuSlot){ x, y, any && c == 0 && r == 0 };
    }
    return n;
}

/* Any menu with the cursor's element list (game_patches_botw.c runtime_ui_hits: the inventory's slots, the Adventure
   Log's quests and tabs, ...): each element's hit box, the bounding pane B_Hit_00 its layout gives for touch (centre and
   size, layout units). The pointer selects only what it is on (user 2026-10-29: hover, nothing between items); the
   selection is walked there with the d-pad, a step along the bigger axis at a time, since the game has no pointer. */
typedef struct { float x, y, w, h; uint64_t id; } MenuHit;   /* id: the game's element (runtime_ui_select) */
static inline int menu_hit_at(const MenuHit *h, int n, double x, double y) {   /* boxes over each other: the smallest */
    int best = -1;
    for (int i = 0; i < n; i++)
        if (fabs(x - h[i].x) <= h[i].w / 2 && fabs(y - h[i].y) <= h[i].h / 2 && (best < 0 || h[i].w * h[i].h < h[best].w * h[best].h)) best = i;
    return best;
}
static inline int menu_hit_step(const MenuHit *h, int from, int to) {
    double dx = h[to].x - h[from].x, dy = h[to].y - h[from].y;
    if (fabs(dx) < 1 && fabs(dy) < 1) return 0;
    return fabs(dy) >= fabs(dx) ? (dy > 0 ? MENU_UP : MENU_DOWN) : (dx > 0 ? MENU_RIGHT : MENU_LEFT);
}
