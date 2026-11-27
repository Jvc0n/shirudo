#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo
# shellcheck disable=SC2016,SC2329 # test_expect_success evaluates the body.
#
# t0012 -- .github/scripts/check-target-tcti.sh: a target that opens
# /dev/tpmrm0 passes, one that tries a TCTI library, never opens the
# device or leaves no trace fails, the command and the TCTI it traces, and
# the usage error, against a stub strace that writes a prepared trace.

cd "$(dirname "$0")/.." || exit 1
# shellcheck source=testing/test-lib.sh
. ./test-lib.sh
S=$(cd .. && pwd)/.github/scripts/check-target-tcti.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export W

# Writes $W/trace.in where -o names, and records the TCTI and the command
# it ran with.
mkdir "$W/bin"
cat >"$W/bin/strace" <<'SH'
#!/bin/sh
while [ $# -gt 0 ]; do
	case $1 in
	-o) out=$2; shift 2 ;;
	-e) shift 2 ;;
	-*) shift ;;
	*) break ;;
	esac
done
printf '%s\n' "${SHIRUDO_TPM_TCTI-}" >"$W/tcti"
printf '%s\n' "$*" >"$W/argv"
cat "$W/trace.in" >"$out"
exit 1
SH
chmod +x "$W/bin/strace"

# One line of a trace each, the way strace prints it.
open_line() {
	printf '1 openat(AT_FDCWD, "%s", %s) = -1 ENOENT (No such file or directory)\n' \
		"$2" "$3" >"$W/$1"
}
open_line device /dev/tpmrm0 'O_RDWR|O_NONBLOCK'
open_line library /usr/lib/libtss2-tcti-device.so.0 'O_RDONLY|O_CLOEXEC'
open_line other /etc/shirudo/shirudo.conf 'O_RDONLY|O_CLOEXEC'

check() {
	PATH="$W/bin:$PATH" sh "$S" /bin/true >"$W/out" 2>"$W/err"
}

test_expect_success 'a target that opens /dev/tpmrm0 passes' '
	cat "$W/other" "$W/device" >"$W/trace.in" &&
	check
'

test_expect_success 'it traces the attest of the binary given' '
	cat "$W/device" >"$W/trace.in" &&
	check &&
	test "$(cat "$W/argv")" = "/bin/true attest"
'

test_expect_success 'the TCTI is pinned to the device' '
	cat "$W/device" >"$W/trace.in" &&
	SHIRUDO_TPM_TCTI=swtpm:port=2321 check &&
	test "$(cat "$W/tcti")" = device:/dev/tpmrm0
'

test_expect_success 'a target that tries a TCTI library fails' '
	cat "$W/library" "$W/device" >"$W/trace.in" &&
	! check &&
	grep -q "tries to load a TCTI library" "$W/err" &&
	grep -q "libtss2-tcti-device.so.0" "$W/err"
'

test_expect_success 'a target that never opens /dev/tpmrm0 fails' '
	cat "$W/other" >"$W/trace.in" &&
	! check &&
	grep -q "never opened /dev/tpmrm0" "$W/err"
'

test_expect_success 'an empty trace fails' '
	: >"$W/trace.in" &&
	! check &&
	grep -q "strace recorded nothing" "$W/err"
'

test_expect_success 'no binary is a usage error' '
	rc=0 &&
	{ sh "$S" >/dev/null 2>&1 || rc=$?; } &&
	test "$rc" -eq 2
'

test_done
