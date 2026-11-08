#!/usr/bin/env bash
# Verify SSH-ramdisk commands inherit the selected VM's ECID.
# shellcheck disable=SC1091,SC2317,SC2329  # the extracted setup stages call these test stubs indirectly
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
create_vm_source=${1:-$root/create-vm.sh}
binder_source=${2:-$create_vm_source}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

sed -n '/^bind_vm_ecid() {$/,/^}$/p' "$binder_source" > "$temporary/bind-ecid.sh"
if [ ! -s "$temporary/bind-ecid.sh" ]; then
  printf 'FAIL: binding implementation is absent\n' >&2
  exit 1
fi
sed -n '/^step sanity   do_sanity$/,/^step gpu-driver do_gpu_driver$/p' "$create_vm_source" > "$temporary/setup-stages.sh"
if [ ! -s "$temporary/setup-stages.sh" ]; then
  printf 'FAIL: source has no bundle-to-firmware setup stages\n' >&2
  exit 1
fi

die() { printf '%s\n' "$*" >&2; exit 1; }

mkdir -p "$temporary/vm"
printf '0x000000000000cafe\n' > "$temporary/vm/ecid"
cat > "$temporary/ssh-ramdisk.sh" <<'EOF'
#!/usr/bin/env bash
if [ -z "${VPHONE_ECID:-}" ]; then
  printf 'FAIL: SSH helper received no ECID selector\n' >&2
  exit 1
fi
printf '%s\0' "$VPHONE_ECID" "$@" > "$ARG_LOG"
EOF
chmod 700 "$temporary/ssh-ramdisk.sh"

run_setup_pipeline() (
  local selector=${1:-}
  unset VPHONE_ECID
  [ -z "$selector" ] || export VPHONE_ECID=$selector
  DRY=0
  VM="$temporary/vm"
  T="$temporary"
  export DRY VM T
  ARG_LOG="$temporary/ssh-arguments"
  export ARG_LOG
  step() { local _label=$1; shift; "$@"; }
  do_sanity() { :; }
  do_bundle() { ECID=$(cat "$VM/ecid"); }
  do_firmware() { "$T/ssh-ramdisk.sh" id; }
  do_gpu_driver() { :; }
  source "$temporary/bind-ecid.sh"
  source "$temporary/setup-stages.sh"
)

run_setup_pipeline
printf '0x000000000000cafe\0id\0' > "$temporary/expected"
cmp "$temporary/expected" "$temporary/ssh-arguments"

rm -f "$temporary/ssh-arguments"
run_setup_pipeline 0xCAFE
cmp "$temporary/expected" "$temporary/ssh-arguments"

rm -f "$temporary/ssh-arguments"
if run_setup_pipeline 0xdead > "$temporary/stdout" 2> "$temporary/stderr"; then
  printf 'FAIL: conflicting ECID was accepted\n' >&2
  exit 1
fi
grep -qx 'VPHONE_ECID does not match the selected VM bundle' "$temporary/stderr"
if [ -e "$temporary/ssh-arguments" ]; then
  printf 'FAIL: SSH helper ran after an ECID conflict\n' >&2
  exit 1
fi

rm -f "$temporary/ssh-arguments"
if run_setup_pipeline 0xnope > "$temporary/stdout" 2> "$temporary/stderr"; then
  printf 'FAIL: malformed ECID was accepted\n' >&2
  exit 1
fi
grep -qx 'VPHONE_ECID must be 1-16 hexadecimal digits, optionally prefixed with 0x' "$temporary/stderr"
if [ -e "$temporary/ssh-arguments" ]; then
  printf 'FAIL: SSH helper ran after a malformed ECID\n' >&2
  exit 1
fi

# A dry run has no resolved bundle yet and must not invent or rewrite a selector.
run_dry_run() (
  DRY=1 ECID=0x0 VPHONE_ECID=0xdead
  export DRY ECID VPHONE_ECID
  source "$temporary/bind-ecid.sh"
  bind_vm_ecid
  [ "$VPHONE_ECID" = 0xdead ]
)
run_dry_run

printf 'OK: setup selects the VM ECID before SSH and rejects malformed or conflicting selectors\n'
