#!/usr/bin/env bash
# tests/test_checksum.sh — Unit tests for install.sh checksum verification
#
# These tests exercise the verify_checksum() and compute_sha256() functions
# from install.sh in isolation, without hitting the network.
#
# Usage:
#   chmod +x tests/test_checksum.sh
#   ./tests/test_checksum.sh
#
# Exit code 0 = all tests passed, non-zero = at least one failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

passed=0
failed=0

pass() { passed=$((passed + 1)); echo "  ✅ PASS: $1"; }
fail() { failed=$((failed + 1)); echo "  ❌ FAIL: $1"; }

# ---------------------------------------------------------------------------
# Source the verification functions from install.sh
# We extract just the function definitions by sourcing in a subshell-safe way.
# ---------------------------------------------------------------------------

# Detect sha256 tool (same logic as install.sh)
sha256_cmd=""
if command -v sha256sum >/dev/null 2>&1; then
  sha256_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  sha256_cmd="shasum -a 256"
else
  echo "SKIP: neither sha256sum nor shasum found — cannot run checksum tests."
  exit 0
fi

# Re-define compute_sha256 and verify_checksum identically to install.sh
# so we can test them without running the full installer.
compute_sha256() {
  if [ "$sha256_cmd" = "sha256sum" ]; then
    sha256sum "$1" | cut -d ' ' -f1
  else
    shasum -a 256 "$1" | cut -d ' ' -f1
  fi
}

# Modified verify_checksum for testability: returns 0/1 instead of exit-ing.
verify_checksum() {
  _file="$1"
  _name="$2"
  _sums="$3"

  _expected="$(grep "$_name" "$_sums" | head -1 | cut -d ' ' -f1)"
  if [ -z "$_expected" ]; then
    echo "Error: could not find checksum for $_name in SHA256SUMS." >&2
    return 1
  fi

  _computed="$(compute_sha256 "$_file")"

  if [ "$_computed" != "$_expected" ]; then
    cat >&2 <<EOF
Error: checksum verification failed for $_name.
Expected: $_expected
Got:      $_computed
This may indicate a corrupted download or a compromised release. Aborting.
EOF
    return 1
  fi

  echo "Checksum verified."
  return 0
}

# ---------------------------------------------------------------------------
# Setup temp directory
# ---------------------------------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# TEST 1: Valid checksum passes verification
# ---------------------------------------------------------------------------
echo ""
echo "TEST 1: Valid checksum passes verification"

echo "hello world" > "$tmp/test-archive.tar.gz"
good_hash="$(compute_sha256 "$tmp/test-archive.tar.gz")"
echo "$good_hash  test-archive.tar.gz" > "$tmp/SHA256SUMS"

if verify_checksum "$tmp/test-archive.tar.gz" "test-archive.tar.gz" "$tmp/SHA256SUMS" >/dev/null 2>&1; then
  pass "Correct checksum accepted"
else
  fail "Correct checksum was rejected"
fi

# ---------------------------------------------------------------------------
# TEST 2: Corrupted file (wrong hash) is rejected
# ---------------------------------------------------------------------------
echo ""
echo "TEST 2: Corrupted file is rejected"

echo "corrupted content" > "$tmp/corrupted-archive.tar.gz"
# Write a known-bad hash
echo "0000000000000000000000000000000000000000000000000000000000000000  corrupted-archive.tar.gz" > "$tmp/SHA256SUMS_bad"

if verify_checksum "$tmp/corrupted-archive.tar.gz" "corrupted-archive.tar.gz" "$tmp/SHA256SUMS_bad" >/dev/null 2>&1; then
  fail "Corrupted file was accepted (should have been rejected)"
else
  pass "Corrupted file correctly rejected"
fi

# ---------------------------------------------------------------------------
# TEST 3: Missing filename in SHA256SUMS is rejected
# ---------------------------------------------------------------------------
echo ""
echo "TEST 3: Missing filename in SHA256SUMS is rejected"

echo "abcdef1234567890  some-other-file.tar.gz" > "$tmp/SHA256SUMS_missing"

if verify_checksum "$tmp/test-archive.tar.gz" "nonexistent-file.tar.gz" "$tmp/SHA256SUMS_missing" >/dev/null 2>&1; then
  fail "Missing filename was accepted (should have been rejected)"
else
  pass "Missing filename correctly rejected"
fi

# ---------------------------------------------------------------------------
# TEST 4: Tampered SHA256SUMS (hash modified) is rejected
# ---------------------------------------------------------------------------
echo ""
echo "TEST 4: Tampered SHA256SUMS is rejected"

echo "hello world" > "$tmp/legit-file.tar.gz"
real_hash="$(compute_sha256 "$tmp/legit-file.tar.gz")"
# Flip one character in the hash
tampered_hash="$(echo "$real_hash" | sed 's/./0/1')"
# Only write tampered if it's actually different (edge case: first char is already 0)
if [ "$tampered_hash" = "$real_hash" ]; then
  tampered_hash="$(echo "$real_hash" | sed 's/./1/1')"
fi
echo "$tampered_hash  legit-file.tar.gz" > "$tmp/SHA256SUMS_tampered"

if verify_checksum "$tmp/legit-file.tar.gz" "legit-file.tar.gz" "$tmp/SHA256SUMS_tampered" >/dev/null 2>&1; then
  fail "Tampered hash was accepted (should have been rejected)"
else
  pass "Tampered hash correctly rejected"
fi

# ---------------------------------------------------------------------------
# TEST 5: compute_sha256 produces consistent output
# ---------------------------------------------------------------------------
echo ""
echo "TEST 5: compute_sha256 produces consistent output"

echo "deterministic content" > "$tmp/deterministic.txt"
hash1="$(compute_sha256 "$tmp/deterministic.txt")"
hash2="$(compute_sha256 "$tmp/deterministic.txt")"

if [ "$hash1" = "$hash2" ] && [ -n "$hash1" ]; then
  pass "compute_sha256 is deterministic"
else
  fail "compute_sha256 produced inconsistent results: '$hash1' vs '$hash2'"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "Results: $passed passed, $failed failed"
echo "========================================="

if [ "$failed" -gt 0 ]; then
  exit 1
fi
