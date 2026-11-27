#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo
#
# .github/scripts/check-target-tcti.sh -- run a target binary's attest
# under strace and check that it opens /dev/tpmrm0 without loading a
# libtss2-tcti library. A target with the device TCTI linked in opens the
# device itself; one whose TPM2-TSS was built without --enable-nodl loads
# that library with dlopen() instead, and a host or an initrd without
# tpm2-tss has none. The machine needs no TPM: the open may fail, the
# check only looks at what the binary tried to open.
#
#   .github/scripts/check-target-tcti.sh <target-binary>
#
# Run it as root, on a host where shirudo is not active: the target makes
# itself undumpable, so strace without CAP_SYS_PTRACE cannot read the
# paths it opens, and an active target refuses SHIRUDO_TPM_TCTI.

set -eu
export LC_ALL=C

if [ "$#" -ne 1 ]; then
	printf 'usage: %s <target-binary>\n' "$0" >&2
	exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

# attest opens the TPM before it needs any state; without a TPM it fails,
# which is expected here. The TCTI is pinned to the default, so neither the
# environment nor a shirudo.conf can point it elsewhere.
SHIRUDO_TPM_TCTI=device:/dev/tpmrm0 \
	strace -f -qq -e 'trace=/^open' -o "$work/trace" "$1" attest \
	>"$work/out" 2>&1 || :

if [ ! -s "$work/trace" ]; then
	printf 'shirudo: strace recorded nothing for %s\n' "$1" >&2
	cat "$work/out" >&2
	exit 1
fi
if grep -q 'libtss2-tcti' "$work/trace"; then
	printf 'shirudo: %s tries to load a TCTI library; build TPM2-TSS with --enable-nodl\n' "$1" >&2
	grep 'libtss2-tcti' "$work/trace" >&2
	exit 1
fi
if ! grep -q '"/dev/tpmrm0"' "$work/trace"; then
	printf 'shirudo: %s never opened /dev/tpmrm0\n' "$1" >&2
	tail -n 20 "$work/trace" >&2
	tail -n 20 "$work/out" >&2
	exit 1
fi
