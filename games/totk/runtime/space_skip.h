#pragma once
/* What Space does (runtime/frontend.m, user 2026-10-29: Space skips cutscenes and goes on through dialogs). In the world
   (a camera action of it updating, game_patches_botw.c runtime_game_world_live) it is X. With no camera action the game
   is in a cutscene, a dialog or a menu. In the inventory and the Adventure Log (their signs: frontend.m pause_tabs_open)
   and on the title screen it confirms (A); X would sort the inventory. Elsewhere it presses A, X and + together: A goes
   on and hurries the text, X or + skips the cutscene (a shrine monk's "Skip X", the blood moon's "Skip +"). A first try counted the frame's draws to tell a cutscene from
   the pause menu and pressed X and + together: a shrine monk's scene did not skip. */
enum { SPACE_WORLD, SPACE_SKIP, SPACE_CONFIRM };
static inline int space_role(int world_live, int title, int menu_tabs) {
    if (world_live) return SPACE_WORLD;
    return title || menu_tabs ? SPACE_CONFIRM : SPACE_SKIP;
}
