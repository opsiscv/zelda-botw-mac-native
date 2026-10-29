#!/bin/zsh
# Test session on Thiago's manual save (the last row of "Select save data to load": the only one without "Autosave").
T=$HOME/Games/botw-test; L="$HOME/Library/Logs/MacNativeGames/botw.log"; I=$T/input.txt
pkill -f "totk-native rewritten"; sleep 2; : > $I; rm -f "$L"; echo off > "$HOME/Library/Application Support/MacNativeGames/BotW/mouse.txt"   # the menu pointer would walk the list back
open -n --env TOTK_DEBUG_LOG=1 --env TOTK_INPUT_FILE=$I --env TOTK_ASSUME_FOCUS=1 ${=EXTRA_ENV} "/Applications/Breath of the Wild.app"
sleep 5; for i in $(seq 1 120); do grep -q "first presented frame" "$L" 2>/dev/null && break; sleep 1; done; sleep 18
echo "key 38 120" >> $I; sleep 6; for k in 1 2 3 4 5 6 7 8; do echo "key 9 150" >> $I; sleep 0.8; done
echo "shot $T/load_list.png" >> $I; sleep 0.5; echo "key 38 120" >> $I; sleep 1.5; echo "key 38 120" >> $I
for i in $(seq 1 60); do echo camsites >> $I; sleep 2; grep -aq "camsites\] Camera[A-Za-z]*: [1-9]" "$L" && break; done; sleep 6

echo "mousemove 1 0" >> $I; sleep 1; echo on > "$HOME/Library/Application Support/MacNativeGames/BotW/mouse.txt"   # mouse mode back on: the riding code only runs in it
