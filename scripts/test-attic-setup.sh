#!/usr/bin/env bash
# Exercise scripts/attic-setup.sh with a fake Bitwarden CLI and a disposable
# install directory. This never reads a real vault, changes a real Bitwarden
# configuration, or writes /etc.
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
setup="$here/attic-setup.sh"
note_name='NixOS Attic Pull Token'
server='https://vault.panic.ac'
wrong_server='https://vault.bitwarden.com'
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
  config)
    [ "${2:-}" = "server" ] || { echo 'unexpected bw config' >&2; exit 2; }
    url=${3:-}
    [ -n "$url" ] || { echo 'bw config server needs a URL' >&2; exit 2; }
    jq --arg url "$url" '.serverUrl = $url' "$FAKE_BW_STATUS" > "$FAKE_BW_STATUS.new"
    mv -- "$FAKE_BW_STATUS.new" "$FAKE_BW_STATUS"
    ;;
  list)
    [ "${2:-}" = "items" ] || { echo 'unexpected bw command' >&2; exit 2; }
    cat -- "$FAKE_BW_ITEMS"
    ;;
  login)
    [ "${2:-}" = "--sso" ] || { echo 'unexpected bw login' >&2; exit 2; }
    exit "${FAKE_BW_LOGIN_STATUS:-0}"
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

make_status() { # path, status, serverUrl-or-empty
  if [ -n "$3" ]; then
    jq -n --arg state "$2" --arg url "$3" \
      '{status: $state, serverUrl: $url, userEmail: "person@example.com"}' > "$1"
  else
    jq -n --arg state "$2" \
      '{status: $state, serverUrl: null, userEmail: "person@example.com"}' > "$1"
  fi
}

make_status "$tmp/status-unlocked.json" unlocked "$server"
make_status "$tmp/status-unlocked-slash.json" unlocked "$server/"
make_status "$tmp/status-locked.json" locked "$server"
make_status "$tmp/status-wrong-locked.json" locked "$wrong_server"
make_status "$tmp/status-wrong-unauthenticated.json" unauthenticated "$wrong_server"
make_status "$tmp/status-no-server.json" unauthenticated ''
printf 'not json\n' > "$tmp/status-bad.json"
status_unreadable="$tmp/status-missing.json"

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

assert_present() {
  local desc=$1 file=$2 needle=$3
  if grep -qF -- "$needle" "$file"; then ok "$desc"; else bad "$desc"; fi
}

reset_logs() {
  : > "$tmp/bw.log"
  : > "$tmp/sudo.log"
}

run_cmd() { # cmd, items, status, out, [path-prefix], [login-exit]
  local cmd=$1 items=$2 status=$3 out=$4 path_prefix=${5:-} login_status=${6:-0}
  local rc
  if PATH="${path_prefix}${fakebin}:$PATH" \
    FAKE_BW_ITEMS="$items" \
    FAKE_BW_STATUS="$status" \
    FAKE_BW_LOG="$tmp/bw.log" \
    FAKE_SUDO_LOG="$tmp/sudo.log" \
    FAKE_ETC_DIR="$etc" \
    ATTIC_SETUP_ETC_DIR="$etc" \
    BW_SESSION='test-session-value' \
    FAKE_BW_LOGIN_STATUS="$login_status" \
    "$setup" "$cmd" >"$out" 2>&1; then
    rc=0
  else
    rc=$?
  fi
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

sentinel='machine attic.panic.ac password previous'
printf '%s\n' "$sentinel" > "$etc/attic.netrc"
chmod 0600 "$etc/attic.netrc"

# attic:setup must reject a missing, wrong, or unreadable server before any note
# lookup, Bitwarden configuration change, or privileged install.
expect_setup_server_failure() {
  local desc=$1 status=$2
  reset_logs
  if run_cmd setup "$cases/one.json" "$status" "$tmp/server-fail-out"; then
    bad "$desc"
  else
    ok "$desc"
  fi
  assert_preserved "$desc leaves the prior file intact" "$sentinel"
  assert_absent "$desc never looks up the note" "$tmp/bw.log" 'list items'
  assert_absent "$desc never changes the Bitwarden server" "$tmp/bw.log" 'config server'
  assert_absent "$desc never starts sudo" "$tmp/sudo.log" 'env -u BW_SESSION'
  assert_absent "$desc does not print the status user" "$tmp/server-fail-out" 'person@example.com'
}

expect_setup_server_failure 'setup rejects a locked session on another server' "$tmp/status-wrong-locked.json"
expect_setup_server_failure 'setup rejects a signed-out session on another server' "$tmp/status-wrong-unauthenticated.json"
expect_setup_server_failure 'setup rejects a missing server configuration' "$tmp/status-no-server.json"
expect_setup_server_failure 'setup rejects an unreadable status' "$status_unreadable"
expect_setup_server_failure 'setup rejects malformed status JSON' "$tmp/status-bad.json"

reset_logs
if run_cmd setup "$cases/one.json" "$tmp/status-locked.json" "$tmp/locked-out"; then
  bad 'setup rejects a locked vault on the intended server'
else
  ok 'setup rejects a locked vault on the intended server'
fi
assert_preserved 'locked vault leaves the prior file intact' "$sentinel"
assert_absent 'locked vault never looks up the note' "$tmp/bw.log" 'list items'
if grep -qF -- 'unlock' "$tmp/locked-out"; then
  ok 'locked vault message names the unlock step'
else
  bad 'locked vault message names the unlock step'
fi

reset_logs
if run_cmd setup "$cases/one.json" "$tmp/status-unlocked.json" "$tmp/out1"; then
  ok 'valid note installs on the intended server'
else
  bad 'valid note installs on the intended server'
fi
assert_eq 'netrc entry is the raw token' "$(cat -- "$etc/attic.netrc")" "machine attic.panic.ac password $token_one"
assert_eq 'netrc mode is 0600' "$(stat -c %a "$etc/attic.netrc")" '600'
assert_eq 'netrc owner is the test user' "$(stat -c %u "$etc/attic.netrc")" "$(id -u)"
assert_eq 'no temporary file remains' "$(find "$etc" -maxdepth 1 -name '.attic.netrc.*' -print)" ''
assert_absent 'token is not printed on success' "$tmp/out1" "$token_one"
assert_absent 'token is not in sudo arguments' "$tmp/sudo.log" "$token_one"
assert_absent 'vault session is not in sudo arguments' "$tmp/sudo.log" 'test-session-value'
assert_present 'exact note name is searched' "$tmp/bw.log" 'list items --search NixOS Attic Pull Token'
assert_present 'install stage strips BW_SESSION' "$tmp/sudo.log" 'env -u BW_SESSION'
assert_present 'non-terminal runs use sudo -n' "$tmp/sudo.log" '-n env -u BW_SESSION'
assert_absent 'setup never changes the Bitwarden server' "$tmp/bw.log" 'config server'
assert_absent 'setup never starts an SSO login' "$tmp/bw.log" 'login --sso'

reset_logs
if run_cmd setup "$cases/two.json" "$tmp/status-unlocked-slash.json" "$tmp/out2"; then
  ok 'a configured server with a trailing slash is accepted'
else
  bad 'a configured server with a trailing slash is accepted'
fi
assert_eq 'rerun writes the new token' "$(cat -- "$etc/attic.netrc")" "machine attic.panic.ac password $token_two"
assert_eq 'rerun keeps mode 0600' "$(stat -c %a "$etc/attic.netrc")" '600'

expect_failure() {
  local desc=$1 items=$2 status=$3
  local out="$tmp/fail-out"
  reset_logs
  if run_cmd setup "$items" "$status" "$out"; then
    bad "$desc"
  else
    ok "$desc"
  fi
  assert_preserved "$desc leaves the prior file intact" "machine attic.panic.ac password $token_two"
  assert_absent "$desc does not print the token" "$out" "$token_one"
  assert_absent "$desc does not print the prior token" "$out" "$token_two"
}

expect_failure 'missing note is rejected' "$cases/none.json" "$tmp/status-unlocked.json"
expect_failure 'ambiguous note is rejected' "$cases/ambiguous.json" "$tmp/status-unlocked.json"
expect_failure 'wrong type is rejected' "$cases/wrong-type.json" "$tmp/status-unlocked.json"
expect_failure 'empty notes are rejected' "$cases/empty.json" "$tmp/status-unlocked.json"
expect_failure 'multiline notes are rejected' "$cases/multiline.json" "$tmp/status-unlocked.json"
expect_failure 'malformed token is rejected' "$cases/malformed.json" "$tmp/status-unlocked.json"
expect_failure 'invalid JWT payload is rejected' "$cases/bad-payload.json" "$tmp/status-unlocked.json"

cp -- "$etc/attic.netrc" "$tmp/valid.netrc"
printf 'machine other.example password keep\n' > "$etc/attic.netrc"
reset_logs
if run_cmd setup "$cases/one.json" "$tmp/status-unlocked.json" "$tmp/unrelated-out"; then
  bad 'unrelated netrc content is refused'
else
  ok 'unrelated netrc content is refused'
fi
assert_eq 'unrelated netrc content is unchanged' "$(cat -- "$etc/attic.netrc")" 'machine other.example password keep'

printf 'machine attic.panic.ac\npassword old\n' > "$etc/attic.netrc"
reset_logs
if run_cmd setup "$cases/one.json" "$tmp/status-unlocked.json" "$tmp/multiline-netrc-out"; then
  ok 'same-machine multiline netrc is refreshable'
else
  bad 'same-machine multiline netrc is refreshable'
fi
assert_eq 'multiline netrc is replaced with one entry' "$(cat -- "$etc/attic.netrc")" "machine attic.panic.ac password $token_one"

printf 'password old\n' > "$etc/attic.netrc"
reset_logs
if run_cmd setup "$cases/one.json" "$tmp/status-unlocked.json" "$tmp/stray-out"; then
  bad 'stray netrc content is refused'
else
  ok 'stray netrc content is refused'
fi
assert_eq 'stray netrc content is unchanged' "$(cat -- "$etc/attic.netrc")" 'password old'

printf 'default password old\n' > "$etc/attic.netrc"
reset_logs
if run_cmd setup "$cases/one.json" "$tmp/status-unlocked.json" "$tmp/default-out"; then
  bad 'default netrc entry is refused'
else
  ok 'default netrc entry is refused'
fi
assert_eq 'default netrc entry is unchanged' "$(cat -- "$etc/attic.netrc")" 'default password old'

rm -f -- "$etc/attic.netrc"
printf 'keep\n' > "$tmp/target.netrc"
ln -s "$tmp/target.netrc" "$etc/attic.netrc"
reset_logs
if run_cmd setup "$cases/one.json" "$tmp/status-unlocked.json" "$tmp/symlink-out"; then
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

reset_logs
if run_cmd setup "$cases/one.json" "$tmp/status-unlocked.json" "$tmp/write-fail-out" "$tmp/failbin:"; then
  bad 'failed atomic replace is reported'
else
  ok 'failed atomic replace is reported'
fi
assert_preserved 'failed replace leaves the prior file intact' "machine attic.panic.ac password $token_two"
assert_eq 'failed replace removes its temporary file' "$(find "$etc" -maxdepth 1 -name '.attic.netrc.*' -print)" ''

# attic:bw-config: no-op when already correct, explicit set otherwise, and no
# change while signed in to another server.
status_config_noop="$tmp/config-noop.json"
cp -- "$tmp/status-unlocked.json" "$status_config_noop"
reset_logs
if run_cmd bw-config "$cases/one.json" "$status_config_noop" "$tmp/config-noop-out"; then
  ok 'bw-config succeeds when the server is already correct'
else
  bad 'bw-config succeeds when the server is already correct'
fi
assert_absent 'bw-config does not rewrite a correct server' "$tmp/bw.log" 'config server'
assert_absent 'bw-config does not log in' "$tmp/bw.log" 'login --sso'
assert_absent 'bw-config does not use sudo' "$tmp/sudo.log" 'env -u BW_SESSION'

status_config_set="$tmp/config-set.json"
cp -- "$tmp/status-wrong-unauthenticated.json" "$status_config_set"
reset_logs
if run_cmd bw-config "$cases/one.json" "$status_config_set" "$tmp/config-set-out"; then
  ok 'bw-config sets the server when signed out'
else
  bad 'bw-config sets the server when signed out'
fi
assert_present 'bw-config runs the exact server command' "$tmp/bw.log" 'config server https://vault.panic.ac'
assert_eq 'bw-config leaves the configured server readable' "$(jq -r '.serverUrl' "$status_config_set")" "$server"
assert_absent 'bw-config does not print the status user' "$tmp/config-set-out" 'person@example.com'
assert_absent 'bw-config does not log in' "$tmp/bw.log" 'login --sso'
assert_absent 'bw-config does not use sudo' "$tmp/sudo.log" 'env -u BW_SESSION'

status_config_no_server="$tmp/config-no-server.json"
cp -- "$tmp/status-no-server.json" "$status_config_no_server"
reset_logs
if run_cmd bw-config "$cases/one.json" "$status_config_no_server" "$tmp/config-no-server-out"; then
  ok 'bw-config sets a missing server'
else
  bad 'bw-config sets a missing server'
fi
assert_present 'bw-config sets a missing server with the exact command' "$tmp/bw.log" 'config server https://vault.panic.ac'

status_config_signed_in="$tmp/config-signed-in.json"
cp -- "$tmp/status-wrong-locked.json" "$status_config_signed_in"
reset_logs
if run_cmd bw-config "$cases/one.json" "$status_config_signed_in" "$tmp/config-signed-in-out"; then
  bad 'bw-config refuses to switch a signed-in server'
else
  ok 'bw-config refuses to switch a signed-in server'
fi
assert_absent 'bw-config does not rewrite a signed-in server' "$tmp/bw.log" 'config server'
assert_present 'bw-config points a signed-in mismatch at the task' "$tmp/config-signed-in-out" 'task attic:bw-config'
assert_eq 'bw-config leaves a signed-in status file unchanged' "$(jq -r '.serverUrl' "$status_config_signed_in")" "$wrong_server"

status_config_bad="$tmp/config-bad.json"
cp -- "$tmp/status-bad.json" "$status_config_bad"
reset_logs
if run_cmd bw-config "$cases/one.json" "$status_config_bad" "$tmp/config-bad-out"; then
  bad 'bw-config rejects unreadable status'
else
  ok 'bw-config rejects unreadable status'
fi
assert_absent 'bw-config does not set the server on unreadable status' "$tmp/bw.log" 'config server'

# attic:bw-login: verify the server first, then launch interactive SSO and
# leave its exit status alone.
reset_logs
if run_cmd bw-login "$cases/one.json" "$tmp/status-locked.json" "$tmp/login-out"; then
  ok 'bw-login starts SSO on the intended server'
else
  bad 'bw-login starts SSO on the intended server'
fi
assert_present 'bw-login runs the exact SSO command' "$tmp/bw.log" 'login --sso'
assert_absent 'bw-login does not change the server' "$tmp/bw.log" 'config server'
assert_absent 'bw-login does not look up the note' "$tmp/bw.log" 'list items'
assert_absent 'bw-login does not use sudo' "$tmp/sudo.log" 'env -u BW_SESSION'

reset_logs
if run_cmd bw-login "$cases/one.json" "$tmp/status-unlocked-slash.json" "$tmp/login-slash-out"; then
  ok 'bw-login accepts a trailing slash on the server'
else
  bad 'bw-login accepts a trailing slash on the server'
fi
assert_present 'bw-login runs SSO with a trailing-slash server' "$tmp/bw.log" 'login --sso'

reset_logs
if run_cmd bw-login "$cases/one.json" "$tmp/status-wrong-locked.json" "$tmp/login-wrong-out"; then
  bad 'bw-login refuses another server before SSO'
else
  ok 'bw-login refuses another server before SSO'
fi
assert_absent 'bw-login does not start SSO on another server' "$tmp/bw.log" 'login --sso'
assert_absent 'bw-login does not look up the note on another server' "$tmp/bw.log" 'list items'
assert_absent 'bw-login does not use sudo on another server' "$tmp/sudo.log" 'env -u BW_SESSION'
assert_present 'bw-login points a mismatch at the task' "$tmp/login-wrong-out" 'task attic:bw-config'

reset_logs
if run_cmd bw-login "$cases/one.json" "$status_unreadable" "$tmp/login-unreadable-out"; then
  bad 'bw-login refuses unreadable status before SSO'
else
  ok 'bw-login refuses unreadable status before SSO'
fi
assert_absent 'bw-login does not start SSO on unreadable status' "$tmp/bw.log" 'login --sso'

reset_logs
set +e
run_cmd bw-login "$cases/one.json" "$tmp/status-locked.json" "$tmp/login-exit-out" '' 7
login_exit=$?
set -e
assert_eq 'bw-login preserves the SSO exit status' "$login_exit" '7'
assert_present 'bw-login reached SSO before exiting' "$tmp/bw.log" 'login --sso'
assert_absent 'bw-login did not install on SSO failure' "$tmp/sudo.log" 'env -u BW_SESSION'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
