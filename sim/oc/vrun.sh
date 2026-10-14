#!/bin/sh
# vrun.sh <objdir> [+args]  (wrapper: clean MSYS2 UCRT64 env)
D=$(cd "$(dirname "$0")" && pwd)
env -i MSYSTEM=UCRT64 HOME=/c/Users/apanc /c/msys64/usr/bin/bash -lc "cd '$D' && ./$1/Vtb.exe $2 $3 $4 $5" | grep -v "^cyc"
