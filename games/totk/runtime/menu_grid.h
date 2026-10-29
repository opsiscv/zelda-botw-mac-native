/* The mouse over Breath of the Wild's inventory (frontend.m): the page as the game shows it, read from its layout
   (game_patches_botw.c runtime_inventory_slots): each slot's place on screen and whether it holds an item. The slot
   under the mouse is the one whose 90 x 90 square holds the pointer, and only a slot with an item counts: anywhere
   else (a gap, an empty slot, off the grid) is nothing. The game has no pointer, so the selection is taken there by
   the shortest path of d-pad steps over item slots only (menu_slot_path): every step lands on an item, so it never
   leaves the page. Layout units (1280 x 720, centre 0,0, y up). Plain C: tests/menu_grid/probe.c. */
#pragma once
#include <math.h>
#include <stdint.h>
#include "menu_pointer.h"

#define MENU_SLOT_HALF 45.0   /* half a slot's square */
#define MENU_SLOT_STEP 98.0   /* from one slot to the next, either way */
#define MENU_GRID_PAGE_LEFT_X -530.0   /* the page on screen: its slots' centres lie between these (the next pages lie further right) */
#define MENU_GRID_PAGE_RIGHT_X -30.0
enum { MENU_SLOTS_MAX = 64 };

typedef struct { float x, y; int item; } MenuSlot;   /* a slot's centre, and whether it holds an item */

/* The item slot under (x, y), -1 for none. */
static inline int menu_slot_at(const MenuSlot *s, int n, double x, double y) {
    for (int i = 0; i < n; i++)
        if (s[i].item && fabs(x - s[i].x) <= MENU_SLOT_HALF && fabs(y - s[i].y) <= MENU_SLOT_HALF) return i;
    return -1;
}

/* The slot one step from slot i that way (MENU_UP / DOWN / LEFT / RIGHT), -1 for none. */
static inline int menu_slot_next(const MenuSlot *s, int n, int i, int way) {
    double dx = way == MENU_RIGHT ? MENU_SLOT_STEP : way == MENU_LEFT ? -MENU_SLOT_STEP : 0;
    double dy = way == MENU_UP ? MENU_SLOT_STEP : way == MENU_DOWN ? -MENU_SLOT_STEP : 0;
    for (int j = 0; j < n; j++) if (fabs(s[j].x - s[i].x - dx) < 2 && fabs(s[j].y - s[i].y - dy) < 2) return j;
    return -1;
}

/* The shortest d-pad path from slot `from` to slot `to` over item slots only: the number of steps written to out (0
   already there), -1 when there is none. */
static inline int menu_slot_path(const MenuSlot *s, int n, int from, int to, int *out, int max) {
    if (from < 0 || to < 0 || from >= n || to >= n) return -1;
    if (from == to) return 0;
    int prev[MENU_SLOTS_MAX], way[MENU_SLOTS_MAX], queue[MENU_SLOTS_MAX], head = 0, tail = 0;
    if (n > MENU_SLOTS_MAX) n = MENU_SLOTS_MAX;
    for (int i = 0; i < n; i++) prev[i] = -2;
    prev[from] = -1; queue[tail++] = from;
    while (head < tail && prev[to] == -2) {
        int i = queue[head++];
        for (int w = MENU_UP; w <= MENU_RIGHT; w++) {
            int j = menu_slot_next(s, n, i, w);
            if (j < 0 || prev[j] != -2 || !s[j].item) continue;
            prev[j] = i; way[j] = w; queue[tail++] = j;
        }
    }
    if (prev[to] == -2) return -1;
    int k = 0;
    for (int i = to; i != from; i = prev[i]) k++;
    if (k > max) return -1;
    for (int i = to, p = k; i != from; i = prev[i]) out[--p] = way[i];
    return k;
}

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
