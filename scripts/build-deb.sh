#!/usr/bin/env bash
#
# build-deb.sh — build a .deb of the patched QEMU (Raspberry Pi 4 GENET + SD->emmc2)
# by reusing Debian's maintained QEMU packaging (salsa qemu-team) on top of the
# razr/qemu fork source. This is a genuine `dpkg-buildpackage` source build — we do
# NOT hand-write debian/.
#
# Strategy:
#   1. Clone the patched QEMU source (razr/qemu @ genet-rebased-sd, incl. submodules
#      so the firmware ROMs are present and Debian's quilt patches all apply).
#   2. Overlay Debian's debian/ packaging from salsa (branch chosen to match the
#      upstream version — experimental tracks 11.1 which matches the fork's 11.0.90).
#   3. Bump d/changelog with a +raspi4genet local version (no other debian/ edits).
#   4. dpkg-buildpackage -b  -> .deb(s) in the parent dir.
#
# Runs inside a per-distro container (ubuntu-24.04 default, debian, eLxr). All
# knobs are environment variables so the GHA workflow can matrix over distros.
set -euo pipefail

# ---- source (the patched QEMU fork) ----------------------------------------
QEMU_REPO="${QEMU_REPO:-https://github.com/razr/qemu}"
QEMU_REF="${QEMU_REF:-genet-rebased-sd}"      # branch or commit

# ---- debian packaging (reused from Debian salsa) ---------------------------
# experimental tracks the newest QEMU (11.1.x) == closest to the fork's 11.0.90.
DEBIAN_REPO="${DEBIAN_REPO:-https://salsa.debian.org/qemu-team/qemu.git}"
DEBIAN_REF="${DEBIAN_REF:-experimental}"

# ---- packaging identity ----------------------------------------------------
# Keep Debian's package names (qemu-system-arm, ...) so the result is a drop-in.
# Append a local version suffix recording the patch set + source commit.
VENDOR_SUFFIX="${VENDOR_SUFFIX:-raspi4genet}"

WORKDIR="${WORKDIR:-$(pwd)/work}"
OUTDIR="${OUTDIR:-$(pwd)/out}"

log() { printf '\n== %s ==\n' "$*"; }

log "Tooling (host/container): $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
command -v dpkg-buildpackage >/dev/null || {
  echo "installing packaging tools"; apt-get update
  apt-get install -y --no-install-recommends \
    git ca-certificates build-essential devscripts equivs quilt \
    dpkg-dev fakeroot
}

rm -rf "$WORKDIR"; mkdir -p "$WORKDIR" "$OUTDIR"
cd "$WORKDIR"

log "Clone patched QEMU source: $QEMU_REPO @ $QEMU_REF (with submodules for ROMs)"
git clone --recurse-submodules --shallow-submodules "$QEMU_REPO" qemu
cd qemu
git checkout "$QEMU_REF"
git submodule update --init --recursive
SRC_SHA="$(git rev-parse --short HEAD)"
UPSTREAM_VER="$(cat VERSION)"
log "Source: VERSION=$UPSTREAM_VER sha=$SRC_SHA"

log "Overlay Debian packaging: $DEBIAN_REPO @ $DEBIAN_REF"
tmp_deb="$(mktemp -d)"
git clone --no-checkout --depth 1 --filter=blob:none -b "$DEBIAN_REF" "$DEBIAN_REPO" "$tmp_deb/pkg"
( cd "$tmp_deb/pkg"
  git sparse-checkout init --cone
  git sparse-checkout set debian
  git checkout )
rm -rf debian
cp -r "$tmp_deb/pkg/debian" ./debian
rm -rf "$tmp_deb"
DEB_BASE_VER="$(dpkg-parsechangelog -l debian/changelog -S Version)"
log "Reused Debian packaging version: $DEB_BASE_VER"

# ---- install build-deps from the reused debian/control ---------------------
log "Install build dependencies (from reused debian/control)"
apt-get update
mk-build-deps --install --remove \
  --tool 'apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y' \
  debian/control

# ---- changelog bump: record patch set + source commit, keep Debian names ---
NEW_VER="${DEB_BASE_VER}+${VENDOR_SUFFIX}1"
log "Add changelog entry: $NEW_VER"
DEBEMAIL="${DEBEMAIL:-ci@razr.local}" DEBFULLNAME="${DEBFULLNAME:-razr qemu-raspi4-deb CI}" \
  dch --newversion "$NEW_VER" --distribution "$(. /etc/os-release; echo "${VERSION_CODENAME:-unstable}")" \
  "Non-maintainer rebuild from razr/qemu@${SRC_SHA} (${QEMU_REF}): Raspberry Pi 4 BCM2838 GENET networking fixes (incl. TX ring-enable) and SD->emmc2 routing. Board-emulation fixes, not guest-OS specific."

# ---- build (binary only; full target set, Debian's rules unmodified) -------
log "dpkg-buildpackage -b"
export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:-nocheck parallel=$(nproc)}"
dpkg-buildpackage -b -us -uc

log "Collect artifacts"
cp -v ../*.deb "$OUTDIR"/ 2>/dev/null || true
ls -l "$OUTDIR"
log "DONE. .deb(s) in $OUTDIR (source $UPSTREAM_VER/$SRC_SHA, pkg $NEW_VER)"
