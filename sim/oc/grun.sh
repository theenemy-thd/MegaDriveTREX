#!/bin/sh
# grun.sh <dir> <args...>: whole-game run in its own folder
D=$(cd "$(dirname "$0")" && pwd)
W=$1; shift
env -i MSYSTEM=UCRT64 HOME=/c/Users/apanc /c/msys64/usr/bin/bash -lc "cd '$D/$W' && ../objg/Vtb.exe +GAME=1 $*" > "$D/$W/run.log" 2>&1
