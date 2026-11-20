#!/usr/bin/env bash
# Exercise scripts/attic-setup.sh with a fake Bitwarden CLI and a disposable
# install directory. This never reads a real vault or writes /etc.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
setup="$here/attic-setup.sh"
note_name='NixOS Attic Pull Token'
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fakebin="$tmp/bin"
etc="$tmp/etc/nix"
mkdir -p "$fakebin" "$etc"
: > "$tmp/sudo.log"
: > "$tmp/bw.log"

cat > "$fakebin/bw" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$FAKE_BW_LOG"
case "${1:-}" in
  status) cat -- "$FAKE_BW_STATUS" ;;
  list)
    [ "${2:-}" = "items" ] || { echo 'unexpected bw command' >&2; exit 2; }
    cat -- "$FAKE_BW_ITEMS"
    ;;
  *) echo 'unexpected bw command' >&2; exit 2 ;;
esac
EOF
chmod +x "$fakebin/bw"

cat > "$fakebin/sudo" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$FAKE_SUDO_LOG"
if [ "${1:-}" = "-n" ]; then shift; fi
[ "${1:-}" = "env" ] || { echo 'unexpected sudo command' >&2; exit 2; }
ATTIC_SETUP_ETC_DIR="$FAKE_ETC_DIR" "$@"
EOF
chmod +x "$fakebin/sudo"

mkdir -p "$tmp/failbin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/failbin/mv"
chmod +x "$tmp/failbin/mv"

status_unlocked="$tmp/status-unlocked.json"
status_locked="$tmp/status-locked.json"
printf '%s\n' '{"status":"unlocked"}' > "$status_unlocked"
printf '%s\n' '{"status":"locked"}' > "$status_locked"

make_jwt() {
  local header payload signature
  header=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | base64 -w0 | tr '+/' '-_' | tr -d '=')
  payload=$(printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '=')
  signature=$(printf '%s' 'signature' | base64 -w0 | tr '+/' '-_' | tr -d '=')
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  printf 'PASS %s\n' "$1"
}
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1"
}

assert_eq() {
  local desc=$1 actual=$2 expected=$3
  if [ "$actual" = "$expected" ]; then ok "$desc"; else bad "$desc (got [$actual], want [$expected])"; fi
}

assert_absent() {
  local desc=$1 file=$2 needle=$3
  if grep -qF -- "$needle" "$file"; then bad "$desc"; else ok "$desc"; fi
}

run_setup() {
  local items=$1 status=$2 out=$3 path_prefix=${4:-}
  set +e
  PATH="${path_prefix}${fakebin}:$PATH" \
    FAKE_BW_ITEMS="$items" \
    FAKE_BW_STATUS="$status" \
    FAKE_BW_LOG="$tmp/bw.log" \
    FAKE_SUDO_LOG="$tmp/sudo.log" \
    FAKE_ETC_DIR="$etc" \
    ATTIC_SETUP_ETC_DIR="$etc" \
    BW_SESSION='test-session-value' \
    "$setup" >"$out" 2>&1
  local rc=$?
  set -e
  return "$rc"
}

assert_preserved() {
  local desc=$1 expected=$2
  assert_eq "$desc" "$(cat -- "$etc/attic.netrc")" "$expected"
}

cases="$tmp/cases"
mkdir -p "$cases"

token_one=$(make_jwt '{"sub":"test","exp":9999999999,"https://jwt.attic.rs/v1":{"caches":{"nixos":{"r":1}}}}')
token_two=$(make_jwt '{"sub":"test2","exp":9999999999,"https://jwt.attic.rs/v1":{"caches":{"nixos":{"r":1}}}}')

jq -n --arg name "$note_name" --arg token "$token_one" \
  '[{type: 2, name: $name, notes: $token}]' > "$cases/one.json"
jq -n --arg name "$note_name" --arg token "$token_two" \
  '[{type: 2, name: $name, notes: $token}]' > "$cases/two.json"
jq -n --arg name "$note_name" \
  '[{type: 2, name: $name, notes: ""}]' > "$cases/empty.json"
jq -n --arg name "$note_name" \
  '[{type: 2, name: $name, notes: "not-a-jwt"}]' > "$cases/malformed.json"
jq -n --arg name "$note_name" --arg token "$token_one" \
  '[{type: 2, name: $name, notes: ($token + "\n" + $token)}]' > "$cases/multiline.json"
jq -n --arg name "$note_name" \
  '[{type: 1, name: $name, notes: "not-a-secure-note"}]' > "$cases/wrong-type.json"
jq -n --arg name "$note_name" --arg token "$token_one" \
  '[{type: 2, name: $name, notes: $token}, {type: 2, name: $name, notes: $token}]' > "$cases/ambiguous.json"
jq -n --arg name "$note_name" --arg token "$token_one" \
  '[{type: 2, name: $name, notes: "eyJhbGciOiJIUzI1NiJ9.notbase64.signature"}]' > "$cases/bad-payload.json"
printf '%s\n' '[]' > "$cases/none.json"

if run_setup "$cases/one.json" "$status_unlocked" "$tmp/out1"; then
  ok 'valid note installs'
else
  bad 'valid note installs'
fi
assert_eq 'netrc entry is the raw token' "$(cat -- "$etc/attic.netrc")" "machine attic.panic.ac password $token_one"
assert_eq 'netrc mode is 0600' "$(stat -c %a "$etc/attic.netrc")" '600'
assert_eq 'netrc owner is the test user' "$(stat -c %u "$etc/attic.netrc")" "$(id -u)"
assert_eq 'no temporary file remains' "$(find "$etc" -maxdepth 1 -name '.attic.netrc.*' -print)" ''
assert_absent 'token is not printed on success' "$tmp/out1" "$token_one"
assert_absent 'token is not in sudo arguments' "$tmp/sudo.log" "$token_one"
assert_absent 'vault session is not in sudo arguments' "$tmp/sudo.log" 'test-session-value'
if grep -qF -- 'list items --search NixOS Attic Pull Token' "$tmp/bw.log"; then
  ok 'exact note name is searched'
else
  bad 'exact note name is searched'
fi
if grep -qF -- 'env -u BW_SESSION' "$tmp/sudo.log"; then
  ok 'install stage strips BW_SESSION'
else
  bad 'install stage strips BW_SESSION'
fi
if grep -qF -- '-n env -u BW_SESSION' "$tmp/sudo.log"; then
  ok 'non-terminal runs use sudo -n instead of letting sudo read the token'
else
  bad 'non-terminal runs use sudo -n instead of letting sudo read the token'
fi

if run_setup "$cases/two.json" "$status_unlocked" "$tmp/out2"; then
  ok 'rerun refreshes the same file'
else
  bad 'rerun refreshes the same file'
fi
assert_eq 'rerun writes the new token' "$(cat -- "$etc/attic.netrc")" "machine attic.panic.ac password $token_two"
assert_eq 'rerun keeps mode 0600' "$(stat -c %a "$etc/attic.netrc")" '600'

expect_failure() {
  local desc=$1 items=$2 status=$3
  local out="$tmp/fail-out"
  if run_setup "$items" "$status" "$out"; then
    bad "$desc"
  else
    ok "$desc"
  fi
  assert_preserved "$desc leaves the prior file intact" "machine attic.panic.ac password $token_two"
  assert_absent "$desc does not print the token" "$out" "$token_one"
  assert_absent "$desc does not print the prior token" "$out" "$token_two"
}

expect_failure 'missing note is rejected' "$cases/none.json" "$status_unlocked"
expect_failure 'ambiguous note is rejected' "$cases/ambiguous.json" "$status_unlocked"
expect_failure 'wrong type is rejected' "$cases/wrong-type.json" "$status_unlocked"
expect_failure 'empty notes are rejected' "$cases/empty.json" "$status_unlocked"
expect_failure 'multiline notes are rejected' "$cases/multiline.json" "$status_unlocked"
expect_failure 'malformed token is rejected' "$cases/malformed.json" "$status_unlocked"
expect_failure 'invalid JWT payload is rejected' "$cases/bad-payload.json" "$status_unlocked"

if run_setup "$cases/one.json" "$status_locked" "$tmp/locked-out"; then
  bad 'locked vault is rejected'
else
  ok 'locked vault is rejected'
fi
assert_preserved 'locked vault leaves the prior file intact' "machine attic.panic.ac password $token_two"
if grep -qF -- 'unlock' "$tmp/locked-out"; then
  ok 'locked vault message names the unlock step'
else
  bad 'locked vault message names the unlock step'
fi

cp -- "$etc/attic.netrc" "$tmp/valid.netrc"
printf 'machine other.example password keep\n' > "$etc/attic.netrc"
if run_setup "$cases/one.json" "$status_unlocked" "$tmp/unrelated-out"; then
  bad 'unrelated netrc content is refused'
else
  ok 'unrelated netrc content is refused'
fi
assert_eq 'unrelated netrc content is unchanged' "$(cat -- "$etc/attic.netrc")" 'machine other.example password keep'

printf 'machine attic.panic.ac\npassword old\n' > "$etc/attic.netrc"
if run_setup "$cases/one.json" "$status_unlocked" "$tmp/multiline-netrc-out"; then
  ok 'same-machine multiline netrc is refreshable'
else
  bad 'same-machine multiline netrc is refreshable'
fi
assert_eq 'multiline netrc is replaced with one entry' "$(cat -- "$etc/attic.netrc")" "machine attic.panic.ac password $token_one"

printf 'password old\n' > "$etc/attic.netrc"
if run_setup "$cases/one.json" "$status_unlocked" "$tmp/stray-out"; then
  bad 'stray netrc content is refused'
else
  ok 'stray netrc content is refused'
fi
assert_eq 'stray netrc content is unchanged' "$(cat -- "$etc/attic.netrc")" 'password old'

printf 'default password old\n' > "$etc/attic.netrc"
if run_setup "$cases/one.json" "$status_unlocked" "$tmp/default-out"; then
  bad 'default netrc entry is refused'
else
  ok 'default netrc entry is refused'
fi
assert_eq 'default netrc entry is unchanged' "$(cat -- "$etc/attic.netrc")" 'default password old'

rm -f -- "$etc/attic.netrc"
printf 'keep\n' > "$tmp/target.netrc"
ln -s "$tmp/target.netrc" "$etc/attic.netrc"
if run_setup "$cases/one.json" "$status_unlocked" "$tmp/symlink-out"; then
  bad 'destination symlink is refused'
else
  ok 'destination symlink is refused'
fi
if [ -L "$etc/attic.netrc" ] && [ "$(cat -- "$tmp/target.netrc")" = 'keep' ]; then
  ok 'symlink and its target are unchanged'
else
  bad 'symlink and its target are unchanged'
fi
cp -- "$tmp/valid.netrc" "$etc/attic.netrc"

if run_setup "$cases/one.json" "$status_unlocked" "$tmp/write-fail-out" "$tmp/failbin:"; then
  bad 'failed atomic replace is reported'
else
  ok 'failed atomic replace is reported'
fi
assert_preserved 'failed replace leaves the prior file intact' "machine attic.panic.ac password $token_two"
assert_eq 'failed replace removes its temporary file' "$(find "$etc" -maxdepth 1 -name '.attic.netrc.*' -print)" ''

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
