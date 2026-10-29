# qemu-raspi4-deb

Builds a `.deb` of a **patched QEMU** that fixes Raspberry Pi 4 (`raspi4b` /
BCM2838) board emulation, from the
[`razr/qemu`](https://github.com/razr/qemu) fork (branch `genet-rebased-sd`).

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
Ubuntu 24.04 ships. So we build the fork's source directly.

## What it builds

A single-target, lean package:

* Builds **only `qemu-system-aarch64`** (the raspi4b emulator) — no other targets,
  no test suite.
* Installs **only the emulator binary** under `/opt/qemu-raspi4/bin/`, plus a
  `/usr/bin/qemu-system-aarch64-raspi4` symlink on `PATH`. No bundled firmware,
  keymaps, or extra tools — raspi4b boots a kernel directly (`-kernel` + `-dtb`)
  and needs none of it.
* Does **not** shadow the distro's own `qemu-system-aarch64`.

Package: `qemu-raspi4`, version `<qemu-version>+raspi4genet.<short-sha>`
(e.g. `11.0.90+raspi4genet.c1359c9`).

## How it works (no hand-maintained upstream packaging)

`scripts/build-deb.sh`:

1. Clones the patched source: `razr/qemu @ genet-rebased-sd` (no submodules — a
   single aarch64 target needs no bundled firmware ROMs).
2. Drops in this repo's minimal `debian/` (control + rules), generates a
   `debian/changelog` recording the source commit.
3. Runs `dpkg-buildpackage -b`. Configure is the verified minimal recipe:
   `--target-list=aarch64-softmmu --disable-docs --enable-slirp`
   (meson auto-pulls the bundled pixman/slirp subprojects — no `-dev` libs).
   Runtime `Depends:` are computed automatically by `dpkg-shlibdeps`.

## Build locally (Ubuntu 24.04)

```bash
bash scripts/build-deb.sh
# -> .deb in ./out/
```

Override the source ref:

```bash
QEMU_REF=<commit-or-branch> bash scripts/build-deb.sh
```

## CI

`.github/workflows/build-deb.yaml` — native build on both `ubuntu-24.04`
(amd64) and `ubuntu-24.04-arm` (arm64) runners (no container, no cross/emulation):

* **workflow_dispatch** — build on demand (optionally pick a `razr/qemu` ref).
* **push tag `v*`** — build and attach the `.deb` to a GitHub Release.

### Artifacts produced

* **Build artifacts** `qemu-raspi4-deb-amd64` and `qemu-raspi4-deb-arm64` — the
  per-arch `out/*.deb` (`qemu-raspi4_<ver>+raspi4genet.<sha>_<arch>.deb`),
  downloadable from the run's Artifacts section. The arm64 `.deb` runs raspi4b
  guests same-arch on an arm64 host (KVM-capable if /dev/kvm is present).
* On a **`v*` tag**: both `.deb`s are also attached to the **GitHub Release**.
* The run log prints the package metadata (`dpkg-deb -f`) and contents
  (`dpkg-deb -c`).

## Consume

```bash
sudo apt-get install -y ./qemu-raspi4_*_amd64.deb
# the patched emulator is now at:
#   /opt/qemu-raspi4/bin/qemu-system-aarch64
#   /usr/bin/qemu-system-aarch64-raspi4   (symlink on PATH)
```

Any tool that runs a `raspi4b` guest points its QEMU-path setting at it, e.g.:

```bash
QEMU=$(command -v qemu-system-aarch64-raspi4)
```

## Validation (what the patches fix)

Validate SD + Ethernet with any aarch64 raspi4b guest (Raspberry Pi OS arm64
and/or a VxWorks raspi4b image). Boot with the stock dtb and `-append`:

```bash
qemu-system-aarch64-raspi4 -machine raspi4b -m 2048 \
  -kernel <kernel> -dtb <rpi-4b.dtb> -append "<boot args>" \
  -nic tap,ifname=tap0,model=bcm2838-genet,script=no,downscript=no \
  -sd <disk.img> -serial null -serial mon:stdio -display none
```

* **SD (emmc2 routing)** — the guest enumerates the SD block device
  (Linux: `/dev/mmcblk*`; VxWorks: `/sd0`).
* **Ethernet (GENET)** — the NIC comes up and pings over `tap0`.

> Verified: the produced `.deb`'s binary boots a VxWorks raspi4b image, mounts
> its SD (`/sd0`), and passes a host↔target ping (0% loss) over the GENET NIC.

## Source pins

| Thing | Value |
|-------|-------|
| QEMU source | `razr/qemu` branch `genet-rebased-sd` (`VERSION` 11.0.90) |
| Target | `aarch64-softmmu` only |
| Build hosts | `ubuntu-24.04` (amd64) + `ubuntu-24.04-arm` (arm64), native |
