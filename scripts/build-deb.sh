#!/usr/bin/env bash
#
# build-deb.sh — build a single-target (aarch64-softmmu) .deb of the patched QEMU
# (Raspberry Pi 4 GENET + SD->emmc2) using a minimal in-repo debian/.
#
# We build ONLY the aarch64 system target (what raspi4b needs), so Debian's
# multi-target packaging is not reused; a small debian/ (control+rules) ships one
# binary and dpkg-shlibdeps computes runtime Depends. Builds natively on
# ubuntu-24.04 (also works in a container or other Debian-like host).
set -euo pipefail

QEMU_REPO="${QEMU_REPO:-https://github.com/razr/qemu}"
QEMU_REF="${QEMU_REF:-genet-rebased-sd}"          # branch or commit
VENDOR_SUFFIX="${VENDOR_SUFFIX:-raspi4genet}"

PKGDIR="$(cd "$(dirname "$0")/.." && pwd)"         # repo root (has debian/)
WORKDIR="${WORKDIR:-$PKGDIR/work}"
OUTDIR="${OUTDIR:-$PKGDIR/out}"

log() { printf '\n== %s ==\n' "$*"; }

log "Host: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"

log "Install packaging + build tooling"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
$SUDO apt-get update
# Host tools per VxDocs qemu/raspberrypi/vxworks.md: git curl ninja meson gcc
# pkg-config dtc. pixman/slirp come from QEMU's bundled meson subprojects (no
# -dev libs needed). Plus the Debian packaging tooling.
$SUDO apt-get install -y --no-install-recommends \
  git curl ca-certificates build-essential debhelper devscripts libdistro-info-perl dpkg-dev fakeroot \
  meson ninja-build gcc pkg-config device-tree-compiler python3 zlib1g-dev

rm -rf "$WORKDIR"; mkdir -p "$WORKDIR" "$OUTDIR"

log "Clone patched QEMU source: $QEMU_REPO @ $QEMU_REF (single target -> no submodules)"
git clone "$QEMU_REPO" "$WORKDIR/qemu"
cd "$WORKDIR/qemu"
git checkout "$QEMU_REF"
SRC_SHA="$(git rev-parse --short HEAD)"
UPSTREAM_VER="$(cat VERSION)"             # e.g. 11.0.90
log "Source: VERSION=$UPSTREAM_VER sha=$SRC_SHA"

log "Place our minimal debian/ into the source tree"
cp -r "$PKGDIR/debian" ./debian

# Native source format -> version has no Debian revision. Record source commit.
PKG_VER="${UPSTREAM_VER}+${VENDOR_SUFFIX}.${SRC_SHA}"
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-stable}")"
log "Generate changelog: qemu-raspi4 $PKG_VER ($CODENAME)"
rm -f debian/changelog
DEBEMAIL="${DEBEMAIL:-ci@razr}" DEBFULLNAME="${DEBFULLNAME:-razr qemu-raspi4-deb CI}" \
  dch --create --package qemu-raspi4 --newversion "$PKG_VER" \
      --distribution "$CODENAME" \
      "Single-target aarch64 build from razr/qemu@${SRC_SHA} (${QEMU_REF}): BCM2838 GENET networking fixes (incl. TX ring-enable) and SD->emmc2 routing for the raspi4b machine."

log "dpkg-buildpackage -b (binary only)"
export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:-nocheck parallel=$(nproc)}"
dpkg-buildpackage -b -us -uc

log "Collect artifacts"
find "$WORKDIR" -maxdepth 1 -name "*.deb" -exec cp -v {} "$OUTDIR"/ \;
ls -l "$OUTDIR"
log "DONE: .deb in $OUTDIR (source $UPSTREAM_VER/$SRC_SHA, pkg $PKG_VER)"
