#pragma once
/* The keyboard's own layout (keys.txt next to controls.txt; user 2026-10-29: remap on the keyboard, not the Switch
   buttons). "key = default key" makes a key do whatever the default key does, in every context (frontend.m: E interacts
   in the world and is the next tab in the pause menu, Space jumps, skips or confirms...); "key = none" leaves it unused;
   keys not named stay themselves. '#' starts a comment, names are case-insensitive. Applied to the window's key codes
   before anything else (frontend.m). Pure C: tests/key_map/probe.c. */
#include <stdint.h>
#include <string.h>
#include <strings.h>

enum { KEY_MAP_SIZE = 128, KEY_MAP_NONE = 255 };
static const struct { const char *name; uint8_t code; } key_map_names[] = {   /* Mac virtual key codes (ANSI) */
    {"a",0},{"s",1},{"d",2},{"f",3},{"h",4},{"g",5},{"z",6},{"x",7},{"c",8},{"v",9},{"b",11},{"q",12},{"w",13},{"e",14},
    {"r",15},{"y",16},{"t",17},{"1",18},{"2",19},{"3",20},{"4",21},{"6",22},{"5",23},{"9",25},{"7",26},{"-",27},
    {"8",28},{"0",29},{"]",30},{"o",31},{"u",32},{"[",33},{"i",34},{"p",35},{"enter",36},{"l",37},{"j",38},{"'",39},
    {"k",40},{";",41},{"\\",42},{",",43},{"/",44},{"n",45},{"m",46},{".",47},{"tab",48},{"space",49},{"`",50},
    {"backspace",51},{"esc",53},{"shift",56},{"caps",57},{"option",58},{"ctrl",59},{"left",123},{"right",124},
    {"down",125},{"up",126}};

static inline void key_map_default(uint8_t map[KEY_MAP_SIZE]) { for (int i = 0; i < KEY_MAP_SIZE; i++) map[i] = (uint8_t)i; }

static inline int key_map_code(const char *s, size_t n) {   /* -1: unknown */
    for (unsigned i = 0; i < sizeof key_map_names / sizeof *key_map_names; i++)
        if (strlen(key_map_names[i].name) == n && !strncasecmp(key_map_names[i].name, s, n)) return key_map_names[i].code;
    return -1;
}

/* Applies a keys.txt text to map. Returns 0, or the 1-based number of the first bad line with *error naming the problem;
   map is then unchanged. */
static inline int key_map_parse(const char *text, uint8_t map[KEY_MAP_SIZE], const char **error) {
    uint8_t next[KEY_MAP_SIZE]; memcpy(next, map, sizeof next);
    int line = 0;
    for (const char *p = text; p && *p;) {
        line++;
        const char *end = strchr(p, '\n'), *stop = end ? end : p + strlen(p), *hash = memchr(p, '#', (size_t)(stop - p));
        if (hash) stop = hash;
        const char *eq = memchr(p, '=', (size_t)(stop - p)), *a = p, *b = eq ? eq + 1 : stop;
        const char *a_end = eq ? eq : stop, *b_end = stop;
        while (a < a_end && (*a == ' ' || *a == '\t' || *a == '\r')) a++;
        while (a_end > a && (a_end[-1] == ' ' || a_end[-1] == '\t')) a_end--;
        while (b < b_end && (*b == ' ' || *b == '\t')) b++;
        while (b_end > b && (b_end[-1] == ' ' || b_end[-1] == '\t' || b_end[-1] == '\r')) b_end--;
        if (a < a_end || eq) {
            if (!eq) { *error = "expected \"key = default key\" or \"key = none\""; return line; }
            int from = key_map_code(a, (size_t)(a_end - a));
            int to = b_end - b == 4 && !strncasecmp(b, "none", 4) ? KEY_MAP_NONE : key_map_code(b, (size_t)(b_end - b));
            if (from < 0 || to < 0) { *error = "unknown key (letters, digits, space enter esc tab shift ctrl option caps backspace up down left right, none)"; return line; }
            next[from] = (uint8_t)to;
        }
        p = end ? end + 1 : NULL;
    }
    memcpy(map, next, sizeof next);
    return 0;
}
