// runtime/mouse_cam.h: the mouse turns the game's camera by its own movement, applied at the camera's next update.
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "mouse_cam.h"

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

static double yaw(const float p[3], const float a[3]) { return atan2(a[0] - p[0], a[2] - p[2]); }   /* as game_patches_botw.c */
static double pitch(const float p[3], const float a[3]) { double dx = a[0] - p[0], dz = a[2] - p[2]; return atan2(a[1] - p[1], sqrt(dx * dx + dz * dz)); }
static double dist(const float p[3], const float a[3]) { return sqrt((p[0] - a[0]) * (p[0] - a[0]) + (p[1] - a[1]) * (p[1] - a[1]) + (p[2] - a[2]) * (p[2] - a[2])); }

int main(void) {
    const float at[3] = { -525.9f, 180.0f, 1993.7f };
    float pos[3] = { -525.9f, 180.0f, 1987.7f };   /* 6 m behind, level */
    double y0 = yaw(pos, at);

    mouse_cam_orbit(pos, at, 0.5, 0);
    check(fabs(remainder(yaw(pos, at) - (y0 - 0.5), 2 * M_PI)) < 1e-4, "mouse right turns the view right by exactly that much (yaw down)");
    check(fabs(dist(pos, at) - 6) < 1e-3, "the distance to the target stays");
    check(fabs(pitch(pos, at)) < 1e-4, "a sideways move leaves the pitch");

    mouse_cam_orbit(pos, at, 0, 0.3);
    check(fabs(pitch(pos, at) + 0.3) < 1e-4, "mouse down looks down by exactly that much");
    check(fabs(dist(pos, at) - 6) < 1e-3, "still the same distance");
    check(fabs(remainder(yaw(pos, at) - (y0 - 0.5), 2 * M_PI)) < 1e-4, "and the same yaw");

    mouse_cam_orbit(pos, at, 0, -5);
    check(fabs(pitch(pos, at) - MOUSE_CAM_PITCH_MAX) < 1e-4, "the pitch stops at its limit");
    mouse_cam_orbit(pos, at, 0, 5);
    check(fabs(pitch(pos, at) + MOUSE_CAM_PITCH_MAX) < 1e-4, "both ways");

    check(fabs(mouse_cam_pitch_deg(8, 0.1, -85, 89) - (8 + 0.1 * 180 / M_PI)) < 1e-4, "mouse down tilts the follow camera down, in its degrees");
    check(mouse_cam_pitch_deg(80, 1, -85, 89) == 89 && mouse_cam_pitch_deg(-80, -1, -85, 89) == -85, "within the game's own limits");

    MouseCamHold hold = {0}; float tilt = 20;
    mouse_cam_hold(&hold, &tilt, 1, 10.0, 4);
    tilt = 5; mouse_cam_hold(&hold, &tilt, 0, 12.0, 4);
    check(tilt == 20, "the tilt the mouse set stays while the hold lasts (the game's return to level is undone)");
    tilt = 5; mouse_cam_hold(&hold, &tilt, 0, 14.5, 4);
    check(tilt == 5, "after the hold the game brings it back");
    tilt = 30; mouse_cam_hold(&hold, &tilt, 1, 20.0, 0); tilt = 5; mouse_cam_hold(&hold, &tilt, 0, 20.1, 0);
    check(tilt == 5, "a hold of 0 is the game's own behaviour");

    MouseCamHold hj = {0}; float t2 = -30;   /* the game shakes it back and forth against the hold (a slope, the tower top) */
    mouse_cam_hold(&hj, &t2, 1, 30.0, 9999);
    float shake[6] = { -29.5f, -30.4f, -29.6f, -30.3f, -29.5f, -30.4f }; int held = 1;
    for (int i = 0; i < 6; i++) { t2 = shake[i]; mouse_cam_hold(&hj, &t2, 0, 30.0 + 0.01 * (i + 1), 9999); if (t2 != -30) held = 0; }
    check(!held, "a tilt the game keeps shaking against is let go instead of fought");
    MouseCamHold hs = {0}; float t3 = -30; mouse_cam_hold(&hs, &t3, 1, 40.0, 9999); int kept = 1;
    for (int i = 0; i < 20; i++) { t3 = -29.8f; mouse_cam_hold(&hs, &t3, 0, 40.0 + 0.01 * (i + 1), 9999); if (t3 != -30) kept = 0; }
    check(kept, "a steady pull back to level (walking) is still held");

    uint8_t after_scope[5] = { 1, 1, 0, 2, 2 }, steered[5] = { 5, 5, 0, 3, 3 }, other[5] = { 2, 2, 0, 3, 3 };
    check(mouse_cam_take_over(after_scope) && !memcmp(after_scope, steered, 5), "after the scope, the mouse takes the camera back as the player's (5 / 3)");
    uint8_t shield[5] = { 5, 5, 0, 1, 1 };
    check(mouse_cam_take_over(shield) && !memcmp(shield, steered, 5), "the shield up (no player input): the mouse is the player's input");
    check(!mouse_cam_take_over(steered), "already the player's: unchanged");
    check(!mouse_cam_take_over(other) && other[0] == 2, "another mode with input is left alone");

    MouseCam c; mouse_cam_reset(&c); double r, d;
    mouse_cam_take(&c, 1.00, &r, &d);
    check(r == 0 && d == 0, "nothing moved, nothing to turn");
    mouse_cam_add(&c, 1.01, 0.1, 0.02); mouse_cam_add(&c, 1.02, 0.2, 0.01);
    mouse_cam_take(&c, 1.03, &r, &d);
    check(fabs(r - 0.3) < 1e-12 && fabs(d - 0.03) < 1e-12, "the camera update takes every movement since the last one");
    mouse_cam_take(&c, 1.06, &r, &d);
    check(r == 0 && d == 0, "and only once: no turning after the mouse stops");
    check(!mouse_cam_live(&c, 1.50), "the camera has not updated for a while: not live");
    mouse_cam_add(&c, 1.50, 0.4, 0);
    mouse_cam_take(&c, 1.51, &r, &d);
    check(r == 0 && d == 0, "movement while the camera did not update (a menu, aiming) is dropped, not saved up for later");
    mouse_cam_add(&c, 1.52, 0.4, 0);
    mouse_cam_take(&c, 1.53, &r, &d);
    check(fabs(r - 0.4) < 1e-12 && mouse_cam_live(&c, 1.53), "once it updates again the mouse turns it again");

    printf("mouse-cam: %d/%d checks pass\n", checked - failures, checked);
    return failures != 0;
}
