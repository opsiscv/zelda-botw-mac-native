#pragma once
#include <stdint.h>
/* What Space does (runtime/frontend.m, user 2026-10-29: "all the skips on Space, X and +, only the skip"). In the world
   (a camera action of it updating, game_patches_botw.c runtime_game_world_live) it is X. With no camera action the
   game is in a menu or a cutscene: a cutscene still draws the world (a few thousand draws a frame, fewer than 1000
   hardly ever: present_hold.h), the pause menu only its still picture and the HUD (130 to 400). In a cutscene Space
   presses X and + together, whichever of them skips it; in a menu or the title screen it confirms (A). */
enum { SPACE_WORLD, SPACE_SKIP, SPACE_CONFIRM };
static inline int space_role(int world_live, int title, uint64_t frame_draws) {
    if (world_live) return SPACE_WORLD;
    return !title && frame_draws >= 1000 ? SPACE_SKIP : SPACE_CONFIRM;
}
