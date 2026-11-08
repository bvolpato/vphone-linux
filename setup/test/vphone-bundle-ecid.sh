#!/usr/bin/env bash
# Verify SSH-ramdisk commands inherit the selected VM's ECID.
# shellcheck disable=SC1091
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
create_vm_source=${1:-$root/create-vm.sh}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

sed -n '/^bind_vm_ecid() {$/,/^}$/p' "$create_vm_source" > "$temporary/bind-ecid.sh"
if [ ! -s "$temporary/bind-ecid.sh" ]; then
  printf 'FAIL: source has no VM ECID binding\n' >&2
  exit 1
fi

die() { printf '%s\n' "$*" >&2; exit 1; }

mkdir -p "$temporary/vm"
printf '0x000000000000cafe\n' > "$temporary/vm/ecid"
cat > "$temporary/ssh-ramdisk.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$VPHONE_ECID" "$@" > "$ARG_LOG"
EOF
chmod 700 "$temporary/ssh-ramdisk.sh"

run_bound_call() (
  DRY=0
  ECID=$(cat "$temporary/vm/ecid")
  ARG_LOG="$temporary/ssh-arguments"
  export ARG_LOG
  source "$temporary/bind-ecid.sh"
  bind_vm_ecid
  "$temporary/ssh-ramdisk.sh" id
)

VPHONE_ECID=0xCAFE run_bound_call
printf '0x000000000000cafe\0id\0' > "$temporary/expected"
cmp "$temporary/expected" "$temporary/ssh-arguments"

rm -f "$temporary/ssh-arguments"
if VPHONE_ECID=0xdead run_bound_call > "$temporary/stdout" 2> "$temporary/stderr"; then
  printf 'FAIL: conflicting ECID was accepted\n' >&2
  exit 1
fi
grep -qx 'VPHONE_ECID does not match the selected VM bundle' "$temporary/stderr"
if [ -e "$temporary/ssh-arguments" ]; then
  printf 'FAIL: SSH helper ran after an ECID conflict\n' >&2
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

printf 'OK: SSH ramdisk selection follows the VM ECID and rejects conflicts\n'
