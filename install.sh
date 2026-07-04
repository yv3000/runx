#!/usr/bin/env sh
set -eu

REPO="${RUNX_REPO:-aryankahar31/runx}"
VERSION="${RUNX_VERSION:-latest}"
INSTALL_DIR="${RUNX_INSTALL_DIR:-$HOME/.runx/bin}"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"

case "$os" in
  linux) platform="linux" ;;
  darwin) platform="macos" ;;
  *) echo "Unsupported OS: $os" >&2; exit 1 ;;
esac

case "$arch" in
  x86_64|amd64) cpu="x64" ;;
  arm64|aarch64) cpu="arm64" ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

asset="runx-${platform}-${cpu}.tar.gz"
if [ "$VERSION" = "latest" ]; then
  base_url="https://github.com/${REPO}/releases/latest/download"
else
  base_url="https://github.com/${REPO}/releases/download/${VERSION}"
fi
url="${base_url}/${asset}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# SHA-256 checksum verification
# ---------------------------------------------------------------------------

# Detect available SHA-256 tool (macOS may lack sha256sum; Linux may lack shasum)
sha256_cmd=""
if command -v sha256sum >/dev/null 2>&1; then
  sha256_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  sha256_cmd="shasum -a 256"
else
  echo "Warning: neither sha256sum nor shasum found; skipping checksum verification." >&2
fi

# Compute the SHA-256 hash of a file and print only the hex digest.
# Usage: compute_sha256 <filepath>
compute_sha256() {
  if [ "$sha256_cmd" = "sha256sum" ]; then
    sha256sum "$1" | cut -d ' ' -f1
  else
    shasum -a 256 "$1" | cut -d ' ' -f1
  fi
}

# Verify a file against a SHA256SUMS manifest.
# Usage: verify_checksum <filepath> <filename> <sha256sums_path>
# Returns 0 on success, exits on failure.
verify_checksum() {
  _file="$1"
  _name="$2"
  _sums="$3"

  _expected="$(grep "$_name" "$_sums" | head -1 | cut -d ' ' -f1)"
  if [ -z "$_expected" ]; then
    echo "Error: could not find checksum for $_name in SHA256SUMS." >&2
    exit 1
  fi

  _computed="$(compute_sha256 "$_file")"

  if [ "$_computed" != "$_expected" ]; then
    cat >&2 <<EOF
Error: checksum verification failed for $_name.
Expected: $_expected
Got:      $_computed
This may indicate a corrupted download or a compromised release. Aborting.
EOF
    exit 1
  fi

  echo "Checksum verified."
}

# ---------------------------------------------------------------------------
# Download, verify, and install
# ---------------------------------------------------------------------------

mkdir -p "$INSTALL_DIR"
echo "Downloading $url"
curl -fsSL "$url" -o "$tmp/$asset"

if [ -n "$sha256_cmd" ]; then
  echo "Downloading SHA256SUMS"
  curl -fsSL "${base_url}/SHA256SUMS" -o "$tmp/SHA256SUMS"
  verify_checksum "$tmp/$asset" "$asset" "$tmp/SHA256SUMS"
fi

tar -xzf "$tmp/$asset" -C "$tmp"
install -m 0755 "$tmp/runx" "$INSTALL_DIR/runx"

echo "Installed runx to $INSTALL_DIR/runx"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Add $INSTALL_DIR to PATH to run runx from any directory." ;;
esac
