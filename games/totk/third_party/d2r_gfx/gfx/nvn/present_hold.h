#pragma once
#include <stdint.h>
/* BOTW (2026-10-28): opening a quick-select bar or the inventory, the first paused frame clears the canvas, stops
   drawing the world and draws only the HUD; the game's still picture of the world (main 1280x720 capture) comes back
   in the next frame. That frame showed a black world for one frame (TOTK_ANOMALY: 3627 draws, then 185, then 394
   with the still picture). A frame of few draws right after a world frame shows the previous picture instead.
   World frames have a few thousand draws (fewer looking at the sky), paused ones 130 to 400: a frame of under a
   quarter of the draws of a world frame (1000 or more) before it. */
static inline int present_hold(uint64_t prev_draws, uint64_t draws) { return prev_draws >= 1000 && draws * 4 < prev_draws; }
