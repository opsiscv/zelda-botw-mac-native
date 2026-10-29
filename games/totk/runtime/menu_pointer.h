/* The mouse in Breath of the Wild's title menu (frontend.m, game_patches_botw.c): the game has no pointer, so the item
   under the mouse is worked out from the screen and the selection is walked there with the d-pad.
   The title layout is 1280x720 (centre 0,0, y up), shown aspect-fit in the view; its five items are lines 40 units
   apart, Continue's centred on y 0, their text right-aligned near the right edge.
   The cursor (part Pa_Cursor_00) frames the selected item; its top-left corner pane N_LT_00 sits at x 981, y 10 - 40 * item. */
#pragma once
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

/* The title has 5 items, or 6 with the DLC (Play in Master Mode): the list is centred, so its first line sits 20 units
   higher per extra item, and the cursor corner's height tells which (10 - 40 * item for 5, 30 - 40 * item for 6). */
enum { MENU_TITLE_MAX = 6 };

/* The item (0..n-1) under the point (view pixels, y up from the bottom), -1 for none: the text of each line,
   right-aligned at x 575, from its own left edge (measured at 1080p), 14 units up and down from the line. */
static inline int menu_title_item(double w, double h, double x, double y, int count) {
    static const double left5[5] = { 493, 477, 505, 513, 378 };        /* Continue, New Game, Options, amiibo, Downloadable Content */
    static const double left6[6] = { 471, 487, 405, 510, 523, 448 };   /* Continue, New Game, Play in Master Mode, Options, amiibo, DLC Purchased */
    const double *left = count == 6 ? left6 : left5; double first = count == 6 ? 20 : 0;
    double s = fmin(w / 1280, h / 720), lx = (x - (w - 1280 * s) / 2) / s - 640, ly = (y - (h - 720 * s) / 2) / s - 360;
    int n = (int)lround((first - ly) / 40);
    if (n < 0 || n >= count || fabs(first - 40 * n - ly) > 14 || lx < left[n] || lx > 590) return -1;
    return n;
}

/* The selected item from the cursor corner's position, and how many items the title has; -1 off the title grid. */
static inline int menu_title_index(float x, float y, int *count) {
    if (fabsf(x - 981) >= 1) return -1;
    for (int c = 5; c <= MENU_TITLE_MAX; c++) {
        double i = (10 + 20 * (c - 5) - y) / 40; int n = (int)lround(i);
        if (fabs(i - n) < 0.02 && n >= 0 && n < c) { *count = c; return n; }
    }
    return -1;
}

/* Other menus (no pointer of their own): the mouse movement walks the selection like the d-pad, a step per
   MENU_STEP_POINTS of movement along the bigger axis (mouse down = down); a step clears the other axis. */
enum { MENU_UP = 1, MENU_DOWN, MENU_LEFT, MENU_RIGHT };
#define MENU_STEP_POINTS 40.0
typedef struct { double x, y; } MenuSteps;
static inline void menu_steps_reset(MenuSteps *m) { m->x = m->y = 0; }
static inline void menu_steps_move(MenuSteps *m, double dx, double dy) { m->x += dx; m->y += dy; }
static inline int menu_steps_next(MenuSteps *m) {
    if (fabs(m->y) >= fabs(m->x) && fabs(m->y) >= MENU_STEP_POINTS) { int s = m->y > 0 ? MENU_DOWN : MENU_UP; m->y -= copysign(MENU_STEP_POINTS, m->y); m->x = 0; return s; }
    if (fabs(m->x) >= MENU_STEP_POINTS) { int s = m->x > 0 ? MENU_RIGHT : MENU_LEFT; m->x -= copysign(MENU_STEP_POINTS, m->x); m->y = 0; return s; }
    return 0;
}

/* Menus with the selection frame (the same cursor layout as the title: the load list, Start / Cancel): its corners
   N_LT_00 and N_RD_00 give the selected item's box in layout units (centre 0,0, y up, 1280x720 shown aspect-fit).
   The title's own cursor is only an arrow (corners 20 units apart), not a box. */
static inline int menu_frame_valid(float left, float top, float right, float bottom) {
    return right - left > 60 && top - bottom > 20 && fabsf(left) < 640 && fabsf(right) < 640 && fabsf(top) < 360 && fabsf(bottom) < 360;
}
/* A small frame is a grid cell (the inventory), where left and right walk the grid; a wide one a list row (saves,
   options), where left and right change the row's value and so are never stepped. */
static inline int menu_frame_small(const float r[4]) { return r[2] - r[0] < 200; }
/* The step (MENU_UP / DOWN / LEFT / RIGHT, 0 for none) that brings the frame r = {left, top, right, bottom} toward the
   point (view pixels, y up), and whether the point is in the frame: up and down first; a list row only up and down and
   only over its column; a grid cell left and right too, on its row. MENU_FRAME_MARGIN keeps a frame from stepping back
   and forth on its edge. */
#define MENU_FRAME_MARGIN 6.0
static inline int menu_frame_step(double w, double h, double x, double y, const float r[4], int *inside) {
    double s = fmin(w / 1280, h / 720), lx = (x - (w - 1280 * s) / 2) / s - 640, ly = (y - (h - 720 * s) / 2) / s - 360;
    *inside = lx >= r[0] && lx <= r[2] && ly <= r[1] && ly >= r[3];
    if (!menu_frame_small(r) && (lx < r[0] - 40 || lx > r[2] + 40)) return 0;
    if (ly > r[1] + MENU_FRAME_MARGIN) return MENU_UP;
    if (ly < r[3] - MENU_FRAME_MARGIN) return MENU_DOWN;
    if (!menu_frame_small(r)) return 0;
    return lx < r[0] - MENU_FRAME_MARGIN ? MENU_LEFT : lx > r[2] + MENU_FRAME_MARGIN ? MENU_RIGHT : 0;
}
/* The frame stays in memory, where it was, after its menu closes, faded out: its pane's alpha (+0x5a) is 0xff while
   its menu shows it and drops (0x0a) once the menu closes. */
static inline int menu_frame_shown(uint8_t alpha) { return alpha >= 0x80; }

/* The wheel by notches (dy: the event's line delta, up positive; returns steps, down = +1): a notch of a ratchet wheel
   arrives as a burst of small events, so the first event after MENU_WHEEL_GAP_S of quiet is one step at once and the
   rest of the burst only adds a step per further whole line (a fast spin). */
#define MENU_WHEEL_GAP_S 0.12
typedef struct { double acc, last; } MenuWheel;
static inline int menu_wheel(MenuWheel *w, double now, double dy) {
    int steps = 0;
    if (dy == 0) return 0;
    if (now - w->last > MENU_WHEEL_GAP_S) { w->acc = 0; steps = dy > 0 ? -1 : 1; }
    else {
        w->acc += dy;
        while (fabs(w->acc) >= 1) { steps += w->acc > 0 ? -1 : 1; w->acc -= copysign(1, w->acc); }
    }
    w->last = now;
    return steps;
}
