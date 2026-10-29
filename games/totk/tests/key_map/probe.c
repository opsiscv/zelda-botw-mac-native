// key_map.h: keys.txt moves the keyboard's keys: "f = e" makes F do what E does (in every context), "e = none" leaves E
// unused; keys not named stay themselves.
#include <stdio.h>
#include "key_map.h"

static int failures, checked;
static void check(int ok, const char *what) { checked++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what); } }

int main(void) {
    uint8_t map[KEY_MAP_SIZE]; const char *error = NULL;
    key_map_default(map);
    check(map[14] == 14 && map[49] == 49 && map[56] == 56, "default: every key is itself");
    check(key_map_parse("# moved interact\nf = e\ne = none\n  Space = shift  \n", map, &error) == 0, "a good file");
    check(map[3] == 14, "F does what E does");
    check(map[14] == KEY_MAP_NONE, "E does nothing");
    check(map[49] == 56, "Space does what Shift does (names are case-insensitive)");
    check(map[13] == 13, "W untouched");
    uint8_t before[KEY_MAP_SIZE]; for (int i = 0; i < KEY_MAP_SIZE; i++) before[i] = map[i];
    check(key_map_parse("w = s\nf = banana\n", map, &error) == 2 && error, "an unknown key: line 2");
    int same = 1; for (int i = 0; i < KEY_MAP_SIZE; i++) same &= map[i] == before[i];
    check(same, "a bad file changes nothing");
    check(key_map_parse("f e\n", map, &error) == 1, "a line without =");
    check(key_map_parse("esc = enter\nleft = a\nctrl = caps\n1 = none\n", map, &error) == 0 && map[53] == 36 && map[123] == 0 && map[59] == 57 && map[18] == KEY_MAP_NONE,
          "named keys: esc enter left ctrl caps 1");
    printf("key_map: %d checks, %d failures\n", checked, failures);
    return failures != 0;
}
