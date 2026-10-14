#!/bin/sh
# vb.sh <objdir> <args>  (wrapper: clean MSYS2 UCRT64 env)
D=$(cd "$(dirname "$0")" && pwd)
O=$1; shift
env -i MSYSTEM=UCRT64 HOME=/c/Users/apanc /c/msys64/usr/bin/bash -lc "cd '$D' && rm -rf $O && ./vbuild.sh $O $*"
