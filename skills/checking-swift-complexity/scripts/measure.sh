#!/usr/bin/env bash
# Measures Swift cyclomatic complexity with swift-complexity and ends with one
# RESULT= line that says whether the scores can be trusted.
#
# Usage: measure.sh <swift-file-or-directory>... [--baseline FILE] [--root DIR] [--fail-on-regression]
#
# Exit status and last line:
#   0  RESULT=pass              no ERROR line; warnings may remain
#   1  RESULT=fail              ERROR lines (error threshold or parse error) or a requested failure
#   2  RESULT=setup-error       no scores: toolchain, build, arguments, or configuration problem
#   3  RESULT=nothing-measured  no callables measured: excluded paths, no Swift files, or no functions
#
# The script lives at <package>/skills/<skill>/scripts. Set SWIFT_COMPLEXITY_PACKAGE
# to a checkout of swift-cyclomatic-complexity-plugin when the skill is installed elsewhere.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="${SWIFT_COMPLEXITY_PACKAGE:-$script_dir/../../..}"

setup_error() {
    printf 'error: %s\n' "$1" >&2
    echo "RESULT=setup-error"
    exit 2
}

[[ $# -gt 0 ]] || setup_error "pass at least one Swift file or directory"
command -v swift >/dev/null 2>&1 || setup_error "swift is not on PATH; the analyzer needs the Swift toolchain that $package/Package.swift declares"
grep -q '"swift-complexity"' "$package/Package.swift" 2>/dev/null ||
    setup_error "no swift-complexity package at $package; set SWIFT_COMPLEXITY_PACKAGE to a checkout of swift-cyclomatic-complexity-plugin"

# Build output stays hidden unless the build fails.
if ! build_log="$(swift build --package-path "$package" --product swift-complexity 2>&1)"; then
    printf '%s\n' "$build_log" >&2
    setup_error "building swift-complexity failed; see the build log above"
fi
bin_dir="$(swift build --package-path "$package" --show-bin-path 2>/dev/null)" ||
    setup_error "could not locate the swift-complexity build products"

stderr_file="$(mktemp)"
trap 'rm -f "$stderr_file"' EXIT

report="$("$bin_dir/swift-complexity" "$@" --format text --explain 2>"$stderr_file")"
status=$?
[[ -n "$report" ]] && printf '%s\n' "$report"
cat "$stderr_file" >&2

case "$status" in
0)
    if grep -q '^INFO .* callables=' <<<"$report"; then
        echo "RESULT=pass"
        exit 0
    fi
    echo "RESULT=nothing-measured"
    exit 3
    ;;
1)
    # swift-complexity reports operational failures as "Error: ..." on stderr.
    if grep -q '^Error:' "$stderr_file"; then
        echo "RESULT=setup-error"
        exit 2
    fi
    echo "RESULT=fail"
    exit 1
    ;;
*)
    echo "RESULT=setup-error"
    exit 2
    ;;
esac
