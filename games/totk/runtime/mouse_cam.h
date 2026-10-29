/* Mouse camera (Mac mouse mode, Breath of the Wild): the mouse turns the camera by its own movement, as on a PC. The
   game's follow camera (CameraChase) starts every update from the camera position it keeps in the camera actor
   (game_patches_botw.c, chase_hook); the movement since the last update (mouse_cam_add, radians: right and down) is
   taken there (mouse_cam_take) and turns that position around its target (mouse_cam_orbit) before the game's update
   runs. No stick, so no top speed and nothing left to turn once the mouse stops. Movement while the follow camera
   does not update (menus, aiming, cutscenes: older than MOUSE_CAM_STALE_S) is dropped, not saved up.
   Plain C with the time passed in: tests/mouse_cam/probe.c. */
#pragma once
#include <math.h>
#include <stdint.h>

#define MOUSE_CAM_PITCH_MAX 1.4   /* radians up or down from level */
#define MOUSE_CAM_STALE_S 0.1

typedef struct { double right, down, last_take; } MouseCam;

static inline void mouse_cam_reset(MouseCam *c) { *c = (MouseCam){0}; }
static inline int mouse_cam_live(const MouseCam *c, double now) { return c->last_take > 0 && now - c->last_take < MOUSE_CAM_STALE_S; }
static inline void mouse_cam_add(MouseCam *c, double now, double right, double down) {
    if (!mouse_cam_live(c, now)) { c->right = c->down = 0; return; }
    c->right += right; c->down += down;
}
static inline void mouse_cam_take(MouseCam *c, double now, double *right, double *down) {
    *right = c->right; *down = c->down; c->right = c->down = 0; c->last_take = now;
}

/* pos turned around at: right turns the view right (its yaw atan2(dx, dz) down), down tilts it down. */
static inline void mouse_cam_orbit(float pos[3], const float at[3], double right, double down) {
    double ox = pos[0] - at[0], oy = pos[1] - at[1], oz = pos[2] - at[2];
    double r = sqrt(ox * ox + oy * oy + oz * oz), h = sqrt(ox * ox + oz * oz);
    if (r < 1e-4 || h < 1e-6) return;
    double c = cos(-right), s = sin(-right), x = ox * c + oz * s, z = -ox * s + oz * c;
    double e = fmax(-MOUSE_CAM_PITCH_MAX, fmin(MOUSE_CAM_PITCH_MAX, atan2(oy, h) + down)), nh = r * cos(e);
    pos[0] = (float)(at[0] + x / h * nh); pos[1] = (float)(at[1] + r * sin(e)); pos[2] = (float)(at[2] + z / h * nh);
}

/* The follow camera's own tilt (degrees below level) after the mouse moved down by that many radians, in its limits. */
static inline float mouse_cam_pitch_deg(float deg, double down, float lo, float hi) {
    return (float)fmax(lo, fmin(hi, deg + down * 180 / M_PI));
}

/* The follow camera brings its tilt back to level on its own; after the mouse tilts it, the tilt is kept for hold
   seconds (each update writes it back), then the game's return goes on. moved: the mouse tilted it this update.
   A tilt the game pushes back and forth (above and below the kept one, MOUSE_CAM_SHAKES times: a slope or the top of a
   tower, where its own limits move) is let go instead of fought, until the mouse tilts it again. */
enum { MOUSE_CAM_SHAKES = 3 };
typedef struct { float tilt; double until; int side, shakes; } MouseCamHold;
static inline void mouse_cam_hold(MouseCamHold *h, float *tilt, int moved, double now, double hold) {
    if (moved) { h->tilt = *tilt; h->until = now + hold; h->side = h->shakes = 0; return; }
    if (now >= h->until) return;
    int side = *tilt > h->tilt + 0.05f ? 1 : *tilt < h->tilt - 0.05f ? -1 : 0;
    if (side && h->side && side != h->side && ++h->shakes >= MOUSE_CAM_SHAKES) { h->until = 0; return; }
    if (side) h->side = side;
    *tilt = h->tilt;
}

/* The follow camera's mode (CameraChase + 0x390, its two copies at +0x390 / +0x391 and the input pair at +0x393 /
   +0x394): 5 / 3 while the player steers it; 1 (+0x390) while it brings itself back behind Link (after the scope, a
   cutscene), and 1 or 2 (+0x393) while it has no player input (the shield up, the return). Without player input it
   works its own position and tilt out and undoes what the mouse writes. The mouse steering it is the player's input,
   as the stick is: 5 / 3. 1: changed. */
static inline int mouse_cam_take_over(uint8_t mode[5]) {
    int changed = 0;
    if (mode[0] == 1) { mode[0] = mode[1] = 5; changed = 1; }
    if (mode[3] != 3 || mode[4] != 3) { mode[3] = mode[4] = 3; changed = 1; }
    return changed;
}
