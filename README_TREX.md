# MegaDriveTREX

A build of the MiSTer Mega Drive / Genesis core (MiSTer-devel/MegaDrive_MiSTer, the Nuked-MD
die-level core) based on the **official release 20260603** (commit `7365a13`), with two extra OSD
options and a save fix for SVP carts:

| OSD option | Values |
|---|---|
| **68K Speed** | Stock 7.6MHz, 10.7MHz, 13.4MHz, 17.9MHz, 17.9MHz Unsafe |
| **Sprite Limit** | On (stock), Off |

Copy `MegaDriveTREX_v7.rbf` (from the GitHub release) to `/media/fat/_Console/`. It sits next to the original core and
uses the same `MegaDrive` config name, so saves and settings are shared.

## 68K Speed

* Only the 68000 runs faster, together with the bus arbiter and I/O chip that answer its bus
  cycles. The VDP (video timing, DMA), Z80, YM2612 and PSG keep their stock clocks, so picture
  timing, refresh rate and music pitch/tempo are unchanged. This is the core equivalent of
  fitting a faster crystal to the 68000 side of a real console.
* The clock is made from the 107.39 MHz core clock: 10.7 MHz = 10 cycles, 13.4 MHz = 8,
  17.9 MHz = 6 (3 high + 3 low). Speed changes happen only at a clock edge and a switch back to
  stock stretches the low phase, so the setting can be changed while a game runs.
* Cartridge ROM lives in SDRAM. When overclocked, the 68000's DTACK is held off until SDRAM has
  returned the data, so reads never see stale ROM data.
* 68000 accesses to the Z80 area ($A00000-$A1FFFF: Z80 RAM, YM2612, Z80 bus request/reset) drop
  the 68000 back to stock speed for about 19 us, so sound-driver handshakes keep their original
  timing. **17.9MHz Unsafe** skips that: faster in games that write the sound chip a lot, but
  music can break in some games.
* Writes to the VDP control port ($C00004-$C00007) also drop to stock speed for about 19 us, in
  every mode including Unsafe. Without it an overclocked 68000-to-VRAM DMA lost its first word
  and tiles were drawn shifted (black blocks and dashes all over the screen).
* Writes to the PSG ($C00011-$C00017) drop to stock speed for about 19 us too, in every mode.
  The PSG takes a new byte only every couple of Z80 clocks; back-to-back writes from a fast
  68000 got mixed up and left a tone playing (Earthion's whistle at its logo).
* SVP carts (Virtua Racing) always run the 68000 at stock speed.
* 17.9 MHz is the ceiling. The Nuked 68000 needs at least 3 core-clock cycles per clock phase;
  21.5 MHz (a 2-cycle phase) fails at once in simulation.
* Games that depend on exact 68000 timing (raster effects timed by CPU loops, some sound
  drivers) may need Stock.

## Sprite Limit Off

The VDP still draws every line exactly as before. A helper renderer (`rtl/md_spr_extra.sv`)
draws the same line again from a shadow copy of VRAM with no sprites-per-line or
pixels-per-line limit, and the VDP's sprite line buffer readout uses those pixels only where
the VDP itself has no sprite pixel. Sprites the VDP had to drop appear; sprite priority,
shadow/highlight, collision flags and everything else the VDP drew are untouched.

* The shadow VRAM is written from the VRAM chip interface, so it sees every write (CPU, DMA
  fill/copy, 68000 DMA).
* The helper follows the sprite link list, the 80/64 sprite table limit, flips and X=0 sprite
  masking, in H32 and H40 (all tested in simulation). Interlace mode 2 is implemented but not
  yet tested.
* Games that use the sprite limit on purpose (to hide sprites behind a mask or a full line of
  sprites) will show those sprites with the limit off: use On for them.
* The helper reads the sprite table from VRAM, not from the VDP's internal sprite cache; games
  that rely on the cache being out of date may differ slightly with the limit off.

## SVP save RAM

SRAM-patched Virtua Racing gets its own 8 KB battery RAM at $200001-$203FFF (odd bytes), so it
can save; stock SVP carts use the save BRAM's port for SVP DRAM.

## Why the release base, and the VDP loop fix

Builds v1-v4 used upstream `main`, which has six unreleased clock and video changes past the
20260603 release; with them sound was wrong even at Stock. From v5 everything is on the official
release, where Stock matches the official core.

The release VDP's CPU-access logic (`ym7101.v` dff12/dff13/dff15) is a combinational loop with no
stable state, so its behaviour depends on routing. v6 carries upstream's later cut of that loop
(from commit `2dc570d`, only the `ym7101.v` part). With it the release core simulates, which is
how the DMA bug above was found.

## Simulation (sim/oc)

Whole-board Verilator bench: real Nuked 68000, VDP, bus arbiter, I/O chip and Z80, BRAM work
RAM and Z80 RAM, cartridge ROM with SDRAM-like latency, the TREX clock generator and DTACK hold.

Build and run (MSYS2 UCRT64 with the `mingw-w64-ucrt-x86_64-verilator` package):

```
cd sim/oc
./vb.sh obj                                   # build
./vrun.sh obj +PERIOD=6 +ARB=1 +SLOW=1        # 68000 test program at 17.9 MHz
./vrun.sh obj +ROM=rom_spr2.hex +LINE=95 +LINE2=125 +SPRU=1 | python cmp_spr.py
```

* `mkrom.py` builds the 68000 test program: ROM, work RAM, MULU/DIVU, VDP VRAM write/read,
  68000-to-VRAM DMA and Z80 RAM through the bus request. `+PERIOD=` is the 68000 clock in core
  clocks (0 = stock), `+ARB=1` lets the arbiter follow it, `+LAT=` sets the ROM latency,
  `+HOLD=0` removes the DTACK hold, `+SLOW=1` adds the Z80-area slowdown, `+TOGGLE=n` flips
  between stock and the set speed every n clocks.
* `mkrom_vdp.py`: display on, long VRAM write bursts (the VDP FIFO fills and holds DTACK) and a
  4096-word 68000-to-VRAM DMA, then a checksum of VRAM. `+VLOG=1` logs every VRAM write.
* `mkrom_spr2.py [h32] [mask]` builds 24 overlapping 16x16 sprites with flips and two palettes
  (`mask`: sprite 20 at X=0), plus a reference render; `cmp_spr.py` compares the bench's video output with it.

Results (v7, release base). Copy `rtl/nuked-md/68k_*code.txt` into `sim/oc` first.

* CPU test: 10.7 / 13.4 / 17.9 MHz identical to stock, also with the Z80-area slowdown and
  with the speed flipping every 331 clocks; 21.5 MHz fails.
* VDP test: identical VRAM at every speed. Without the control-port slowdown, the DMA lost its
  first word at every overclocked speed; with the arbiter left at stock instead, Z80 RAM reads
  went wrong at 15.3 MHz and up.
* PSG test (`mkrom_psg2.py`, Earthion's 12-byte PSG silence burst): without the PSG slowdown the
  PSG is left with a tone at 13.4, 15.3 and 17.9 MHz depending on timing; with it the PSG is
  silent at every speed and offset.
* Whole-game run (`+GAME=1`, `rom_game.hex`, SSF mapper; logs YM2612 writes, audio and
  screenshots): Earthion at 17.9 MHz played a 7.4 kHz tone at sound start before the fix,
  nothing after it.
* Sprite tests: Limit Off matches the reference in H40, H32 and with X=0 masking.

Earlier results (v1, upstream main):

| 68000 clock | Arbiter at stock | Arbiter follows 68000 |
|---|---|---|
| 10.7 MHz | OK | OK |
| 13.4 MHz | OK | OK |
| 15.3 MHz | Z80 RAM reads wrong | OK |
| 17.9 MHz | OK (by luck) | OK, 1.86x faster test run |
| 21.5 MHz | crash | crash |

ROM latency 6-24 core clocks: OK with the DTACK hold; without it 17.9 MHz crashes from 16
clocks of latency. Switching speed every 113, 331 or 997 clocks: OK. Sprite test: with the
limit on, lines 100-105 lose sprites (as on hardware); with it off every line 95-125 matches
the reference, in H40, H32 and with an X=0 masking sprite.

## Building

Quartus Prime Lite 17.0: open `MegaDrive.qpf` and compile, or
`quartus_sh --flow compile MegaDrive -c MegaDrive`, then rename `output_files/MegaDrive.rbf`
to `MegaDriveTREX.rbf`. Worst-case setup slack on the build laptop: v7 -2.24 ns; the untouched
20260603 release built the same way gives -2.55 ns (its own 68000 data paths).

## Changed files

* `MegaDrive.sv`: OSD entries (status bits 64-67), clock generator, Z80-area slowdown, DTACK
  hold and sprite option wiring.
* `rtl/m68k_clkgen.sv` (new): 68000 / arbiter clock generator.
* `rtl/md_spr_extra.sv` (new): Sprite Limit Off helper renderer.
* `rtl/cartridge.sv`: `cart_rom_wait` output (ROM read waiting for SDRAM).
* `rtl/nuked-md/md_board.v`: arbiter clock input, DTACK hold, helper renderer instance.
* `rtl/nuked-md/ym7101.v`, `fc1004.v`, `vram.v`: helper renderer ports, display merge, VRAM
  write snoop; VDP CPU-access loop cut in `ym7101.v`.
* `rtl/cartridge.sv`: SVP battery RAM, `cart_svp` output.
* `sim/oc`: test benches.
