// key_icons_swap.h: key_icons.bin holds the button icons' sheet twice (the world's keys, the menu's); the runtime finds
// the sheet in the game's memory and puts in the one for where the game is.
#include <stdio.h>
#include <stdlib.h>
#include "key_icons_swap.h"

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

int main(void) {
    enum { SIZE = 4096 };
    uint8_t file[12 + 2 * SIZE]; memcpy(file, "KICO", 4); uint32_t one = 1, size = SIZE; memcpy(file + 4, &one, 4); memcpy(file + 8, &size, 4);
    uint8_t *world = file + 12, *menu = world + SIZE;
    for (int i = 0; i < SIZE; i++) world[i] = menu[i] = (uint8_t)(i * 13);
    memset(menu + 1000, 0xAA, 300);
    KeyIcons k;
    check(key_icons_load(&k, file, sizeof file) == 0 && k.count == 1 && k.size == SIZE, "a good file");
    check(key_icons_load(&k, file, sizeof file - 1) != 0, "a short file is refused");
    key_icons_load(&k, file, sizeof file);
    check(k.needle[0] <= 1000 && k.needle[0] + KEY_ICONS_NEEDLE > 1000, "the needle covers where the two sheets differ");
    uint8_t mem[SIZE]; memcpy(mem, world, SIZE);
    check(key_icons_which(&k, 0, mem) == 0, "the world's sheet");
    memcpy(mem, menu, SIZE);
    check(key_icons_which(&k, 0, mem) == 1, "the menu's sheet");
    mem[5] ^= 1;
    check(key_icons_which(&k, 0, mem) < 0, "something else");
    check(key_icons_sheet(&k, 0, 1) == menu && key_icons_sheet(&k, 0, 0) == world, "the sheets in the file");
    printf("key_icons: %d checks, %d failures\n", checked, failures);
    return failures != 0;
}
