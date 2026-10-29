#pragma once
/* The button icons follow where the game is (user 2026-10-29: in the pause menu Select is the left click, Back is Esc,
   System is E). thiago/scripts/key_icons.py writes the font's icon sheet with the world's keys into the RomFS mod, and
   key_icons.bin next to controls.txt: "KICO", u32 count, u32 size, then count pairs of sheets as stored (swizzled BC4),
   the world's and the menu's. game_patches_botw.c finds the sheet in the game's memory and copies the other one over it
   when the world stops or goes on (the graphics layer re-uploads a texture whose memory the CPU wrote). The needle: a
   window where the two sheets of a pair differ, so a hit is one of ours. Pure C: tests/key_icons/probe.c. */
#include <stdint.h>
#include <string.h>

enum { KEY_ICONS_MAX = 8, KEY_ICONS_NEEDLE = 256 };
typedef struct { const uint8_t *data; uint32_t count, size; uint32_t needle[KEY_ICONS_MAX]; } KeyIcons;

static inline const uint8_t *key_icons_sheet(const KeyIcons *k, unsigned pair, int menu) { return k->data + (size_t)(2 * pair + !!menu) * k->size; }

static inline int key_icons_load(KeyIcons *k, const uint8_t *file, size_t n) {   /* 0: loaded */
    if (n < 12 || memcmp(file, "KICO", 4)) return -1;
    memcpy(&k->count, file + 4, 4); memcpy(&k->size, file + 8, 4);
    if (!k->count || k->count > KEY_ICONS_MAX || k->size < KEY_ICONS_NEEDLE || n != 12 + (size_t)k->count * 2 * k->size) return -1;
    k->data = file + 12;
    for (unsigned p = 0; p < k->count; p++) {
        const uint8_t *w = key_icons_sheet(k, p, 0), *m = key_icons_sheet(k, p, 1); uint32_t i = 0;
        while (i < k->size && w[i] == m[i]) i++;
        k->needle[p] = i + KEY_ICONS_NEEDLE <= k->size ? i : k->size - KEY_ICONS_NEEDLE;
    }
    return 0;
}

/* Which sheet of the pair mem holds (size bytes): 0 the world's, 1 the menu's, -1 neither. */
static inline int key_icons_which(const KeyIcons *k, unsigned pair, const uint8_t *mem) {
    for (int menu = 0; menu < 2; menu++) if (!memcmp(mem, key_icons_sheet(k, pair, menu), k->size)) return menu;
    return -1;
}
