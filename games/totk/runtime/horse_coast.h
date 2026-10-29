#pragma once
/* The horse with W let go (runtime/input.c horse_brake; user 2026-10-29: it must not stop at once, it slows down over
   time, S brakes for real). The game keeps the horse's gait with the stick at the centre, so it is reined in (the stick
   back, as S does) in short pulls: after a moment, a pull every period, until it has stopped. S held pulls it all the
   time. */
#include <stdint.h>
#define HORSE_COAST_DELAY_NS 500000000ull    /* let go: it keeps going this long before the first pull */
#define HORSE_COAST_PERIOD_NS 700000000ull   /* one pull each period ... */
#define HORSE_COAST_PULL_NS 120000000ull     /* ... this long */
static inline int horse_coast_rein(uint64_t since_release_ns) {
    return since_release_ns >= HORSE_COAST_DELAY_NS && (since_release_ns - HORSE_COAST_DELAY_NS) % HORSE_COAST_PERIOD_NS < HORSE_COAST_PULL_NS;
}
/* W / A / D as the rider's stick (game_patches_botw.c horse_ai_hook): k is W 1, A 4, D 8. W with A or D curves at
   67.5 degrees, halfway between 45 (it turned too little, user 2026-10-29) and A or D alone. */
static inline void horse_steer(int k, float *fwd, float *side) {
    *fwd = (k & 1) ? 1 : 0; *side = (k & 8) ? 1 : (k & 4) ? -1 : 0;
    if (*fwd && *side) { *fwd = 0.38268343f; *side *= 0.92387953f; }
}
