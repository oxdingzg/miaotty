# miaotty shell additions — source after the core (Ghostty) integration.
# The core integration owns OSC 133/7/9;4; this file only adds the miaotty CLI
# wrapper and documents the injected environment.

# Injected by the app; listed here for reference.
: "${MIAOTTY_SOCKET:=${TMPDIR:-/tmp}miaotty.sock}"
: "${MIAOTTY_PROTO:=1}"
export MIAOTTY_SOCKET MIAOTTY_PROTO

miaotty() {
  if command -v miaotty-cli >/dev/null 2>&1; then
    miaotty-cli --socket "$MIAOTTY_SOCKET" "$@"
  else
    echo "miaotty: miaotty-cli not found on PATH" >&2
    return 127
  fi
}
