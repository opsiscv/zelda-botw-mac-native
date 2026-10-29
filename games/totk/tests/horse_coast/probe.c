// horse_coast.h: with W let go the horse slows down over time (the rein pulled in short pulls), it does not stop at once;
// S held pulls it all the time (runtime/input.c).
#include <math.h>
#include <stdio.h>
#include "horse_coast.h"

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

int main(void) {
    const uint64_t ms = 1000000;
    check(!horse_coast_rein(0), "just let go: not reined in");
    check(!horse_coast_rein(HORSE_COAST_DELAY_NS - ms), "before the delay: not reined in");
    check(horse_coast_rein(HORSE_COAST_DELAY_NS), "after the delay: a pull");
    check(!horse_coast_rein(HORSE_COAST_DELAY_NS + HORSE_COAST_PULL_NS), "after the pull: let go again");
    check(horse_coast_rein(HORSE_COAST_DELAY_NS + HORSE_COAST_PERIOD_NS), "the next pull");
    int on = 0; for (uint64_t t = 0; t < 10000 * ms; t += ms) on += horse_coast_rein(t);
    check(on > 0 && on < 5000, "over 10 s the rein is pulled less than half the time");
    float f, d;
    horse_steer(1, &f, &d); check(f == 1 && d == 0, "W: straight on");
    horse_steer(8, &f, &d); check(f == 0 && d == 1, "D: turn on the spot");
    horse_steer(1 | 4, &f, &d); check(d < 0 && -d > 0.85f && -d < 0.95f && f > 0.3f && fabsf(f * f + d * d - 1) < 1e-4f, "W+A: halfway between a 45 degree curve and A alone");
    printf("horse_coast: %d checks, %d failures\n", checked, failures);
    return failures != 0;
}
