# qemu-raspi4-deb

Builds a Debian/Ubuntu `.deb` of a **patched QEMU** that fixes Raspberry Pi 4
(`raspi4b` / BCM2838) board emulation, by reusing Debian's maintained QEMU
packaging on top of the [`razr/qemu`](https://github.com/razr/qemu) fork
(branch `genet-rebased-sd`).

These are **board-emulation fixes, not guest-OS specific** — any aarch64 guest on
QEMU's `raspi4b` machine benefits:

* **BCM2838 GENET** Ethernet model fixes (incl. the TX ring-enable fix), so the
  on-board NIC works under emulation.
* **SD card routed to emmc2**, so emmc2-only guests (e.g. VxWorks) see the SD.

The fix set originates from `robwoolley/qemu` (GENET) plus an SD→emmc2 commit,
rebased onto QEMU 11.1-dev (`VERSION` = `11.0.90`).

## Why this exists

Upstream and distro QEMU don't yet carry these raspi4b fixes, and the model
targets recent QEMU APIs (11.x) — it does **not** back-port to the QEMU 8.2 that
Ubuntu 24.04 ships. So we build the fork's source with a real
`dpkg-buildpackage`, reusing Debian's packaging rather than hand-writing one.

## How it works (no hand-written `debian/`)

`scripts/build-deb.sh`:

1. Clones the patched source: `razr/qemu @ genet-rebased-sd` (with submodules, so
   the firmware ROMs are present and Debian's quilt patches apply).
2. Overlays Debian's `debian/` packaging from
   [salsa qemu-team](https://salsa.debian.org/qemu-team/qemu) branch
   `experimental` — which tracks QEMU **11.1**, matching the fork's `11.0.90`.
3. Bumps `debian/changelog` with a `+raspi4genet` local version (recording the
   source commit). No other `debian/` edits — Debian's rules build the full,
   tested target set.
4. Runs `dpkg-buildpackage -b` → standard QEMU `.deb`s (`qemu-system-arm`, …).

Because the package **keeps Debian's names/versions** (e.g.
`1:11.1.0~rc3+ds-2+raspi4genet1`), it's a drop-in: installing it provides a
`qemu-system-aarch64` with the raspi4b fixes.

## Build locally

```bash
# In an ubuntu-24.04 / debian / eLxr environment (or container):
bash scripts/build-deb.sh
# -> .deb(s) in ./out/
```

Override the source ref or Debian packaging branch via env:

```bash
QEMU_REF=<commit> DEBIAN_REF=experimental bash scripts/build-deb.sh
```

## CI

`.github/workflows/build-deb.yaml`:

* **workflow_dispatch** — build on demand; choose the container distro
  (`ubuntu-24.04` default, `debian-trixie`, `elxr`) and optionally a `razr/qemu`
  ref.
* **push tag `v*`** — build all distros and attach the `.deb`(s) to a GitHub
  Release.

## Consume

```bash
sudo apt-get install -y ./qemu-system-arm_*+raspi4genet1_*.deb
# qemu-system-aarch64 now carries the raspi4b GENET + SD fixes.
```

Downstream consumers point their QEMU-path env at it:

* VxWorks ROS 2 test harness: `VX_QEMU=$(command -v qemu-system-aarch64)`
* qemu-mcp: `QEMU_RASPI4_BIN=$(command -v qemu-system-aarch64)`

## Source pins

| Thing | Value |
|-------|-------|
| QEMU source | `razr/qemu` branch `genet-rebased-sd` (`VERSION` 11.0.90) |
| Debian packaging | salsa `qemu-team/qemu` branch `experimental` (QEMU 11.1) |
| Default build distro | `ubuntu-24.04` (also `debian-trixie`, `elxr`) |
