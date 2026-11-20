#!/usr/bin/env bash
# Install the Attic reader credential for the Nix daemon from Bitwarden.
#
# The Bitwarden item is a secure note named "NixOS Attic Pull Token". Its Notes
# body is one raw Attic pull token (a JWT). The token is installed as the only
# entry in /etc/nix/attic.netrc, owned by root with mode 0600, so the Nix daemon
# can read the private cache without per-command flags.
#
# The bw-config and bw-login commands prepare the Bitwarden CLI for the
# self-hosted vault. setup verifies that server before it reads the note, so a
# cloud or other-server session can never supply the credential.
#
# The privileged install is a fixed inline script with the fixed destination
# /etc/nix/attic.netrc. It receives only the validated netrc entry on stdin;
# the checkout script path is not executed as root and production code has no
# caller-controlled destination or test override.
set -eu

NOTE_NAME='NixOS Attic Pull Token'
NETRC_MACHINE='attic.panic.ac'
NETRC_PATH='/etc/nix/attic.netrc'
BW_SERVER='https://vault.panic.ac'

die() {
  printf 'attic-setup: %s\n' "$*" >&2
  exit 1
}

status_field() {
  printf '%s' "$1" | jq -r --arg field "$2" '.[$field] // empty' 2>/dev/null
}

same_server() {
  [ "${1%/}" = "$BW_SERVER" ]
}

require_bw_server() {
  local server
  server=$(status_field "$1" serverUrl) \
    || die 'could not read the Bitwarden server configuration; run task attic:bw-config'
  [ -n "$server" ] \
    || die 'the Bitwarden CLI has no server configured; run task attic:bw-config'
  same_server "$server" \
    || die "the Bitwarden CLI is configured for $server, not $BW_SERVER; run task attic:bw-config"
}

install_netrc() {
  local netrc_line=$1 root_script
  root_script=$(cat <<'ROOT_SCRIPT'
set -eu
dest=/etc/nix/attic.netrc
[ -d /etc/nix ] || { echo 'attic-setup: /etc/nix does not exist' >&2; exit 1; }
[ ! -L "$dest" ] || { echo 'attic-setup: refusing to replace the symlink at /etc/nix/attic.netrc' >&2; exit 1; }
if [ -e "$dest" ]; then
  [ -f "$dest" ] || { echo 'attic-setup: refusing to replace the non-regular file /etc/nix/attic.netrc' >&2; exit 1; }
  entries=$(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "machine") ours = ($(i + 1) == "attic.panic.ac")
        else if ($i == "default") print "default"
        else if (!ours) print "stray"
      }
    }
  ' "$dest") || { echo 'attic-setup: cannot read the existing /etc/nix/attic.netrc' >&2; exit 1; }
  [ -z "$entries" ] || { echo 'attic-setup: refusing to overwrite /etc/nix/attic.netrc: it names another netrc entry' >&2; exit 1; }
fi
umask 077
tmp=$(mktemp /etc/nix/.attic.netrc.XXXXXX) || { echo 'attic-setup: cannot create a temporary file in /etc/nix' >&2; exit 1; }
trap 'rm -f -- "$tmp"' EXIT
cat > "$tmp"
[ -s "$tmp" ] || { echo 'attic-setup: no credential was provided on stdin' >&2; exit 1; }
[ "$(grep -c '' "$tmp")" -eq 1 ] || { echo 'attic-setup: the credential is not a single netrc entry' >&2; exit 1; }
grep -Eq '^machine attic\.panic\.ac login attic password [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' "$tmp" \
  || { echo 'attic-setup: the credential is not the expected Attic netrc entry' >&2; exit 1; }
chmod 0600 "$tmp"
chown root:root "$tmp"
mv -f -- "$tmp" "$dest"
tmp=''
ROOT_SCRIPT
)
  local sudo_flags=()
  [ -t 0 ] || sudo_flags=(-n)
  printf '%s\n' "$netrc_line" \
    | sudo "${sudo_flags[@]}" env -u BW_SESSION -- sh -c "$root_script" \
    || die 'installing the credential failed; the previous file was left unchanged (run from an interactive terminal if sudo needs a password)'
}

bw_config() {
  command -v bw >/dev/null 2>&1 || die 'the Bitwarden CLI (bw) is not on PATH'
  command -v jq >/dev/null 2>&1 || die 'jq is not on PATH'

  status_json=$(bw status 2>/dev/null) || die 'could not read Bitwarden status'
  server=$(status_field "$status_json" serverUrl) || die 'could not read the Bitwarden server configuration'
  state=$(status_field "$status_json" status) || die 'could not read the Bitwarden status'

  if same_server "$server"; then
    printf 'The Bitwarden CLI already uses %s.\n' "$BW_SERVER"
    return 0
  fi
  if [ -n "$state" ] && [ "$state" != 'unauthenticated' ]; then
    die "the Bitwarden CLI is signed in on ${server:-an unconfigured server}; refusing to switch servers. Sign out or use a separate CLI profile, then run task attic:bw-config."
  fi

  bw config server "$BW_SERVER" || die 'could not configure the Bitwarden CLI server'
  status_json=$(bw status 2>/dev/null) || die 'could not verify the Bitwarden server configuration'
  server=$(status_field "$status_json" serverUrl) || die 'could not verify the Bitwarden server configuration'
  same_server "$server" \
    || die "the Bitwarden CLI reports ${server:-no server} after configuration; expected $BW_SERVER"
  printf 'The Bitwarden CLI now uses %s.\n' "$BW_SERVER"
}

bw_login() {
  command -v bw >/dev/null 2>&1 || die 'the Bitwarden CLI (bw) is not on PATH'
  command -v jq >/dev/null 2>&1 || die 'jq is not on PATH'

  status_json=$(bw status 2>/dev/null) || die 'could not read Bitwarden status; run task attic:bw-config first'
  require_bw_server "$status_json"
  bw login --sso
}

attic_setup() {
  command -v bw >/dev/null 2>&1 || die 'the Bitwarden CLI (bw) is not on PATH'
  command -v jq >/dev/null 2>&1 || die 'jq is not on PATH'
  command -v sudo >/dev/null 2>&1 || die 'sudo is not on PATH'

  status_json=$(bw status 2>/dev/null) || die 'could not read Bitwarden status; run task attic:bw-config and task attic:bw-login first'
  require_bw_server "$status_json"
  [ "$(status_field "$status_json" status)" = 'unlocked' ] \
    || die 'Bitwarden is not unlocked; run "bw unlock" and export BW_SESSION in this shell before this task'

  items=$(bw list items --search "$NOTE_NAME" 2>/dev/null) \
    || die 'could not list Bitwarden items; check the session and try again'
  printf '%s' "$items" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || die 'Bitwarden returned an unexpected item list'

  matches=$(printf '%s' "$items" | jq --arg name "$NOTE_NAME" \
    '[.[] | select(.name == $name and .type == 2)] | length' 2>/dev/null) \
    || die 'could not parse the Bitwarden item list'
  case "$matches" in
    1) ;;
    0) die "no secure note named \"$NOTE_NAME\" is available; run \"bw sync\" if it was just created" ;;
    *) die "more than one secure note is named \"$NOTE_NAME\"; keep exactly one" ;;
  esac

  raw=$(printf '%s' "$items" | jq -r --arg name "$NOTE_NAME" \
    '[.[] | select(.name == $name and .type == 2)][0].notes // empty' 2>/dev/null) \
    || die 'could not read the selected Bitwarden note'
  token=${raw#"${raw%%[![:space:]]*}"}
  token=${token%"${token##*[![:space:]]}"}
  [ -n "$token" ] || die "the \"$NOTE_NAME\" note has an empty Notes body"
  case "$token" in
    *[[:space:]]*) die "the \"$NOTE_NAME\" Notes body must be one raw token, not multiple lines" ;;
  esac
  [[ $token =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] \
    || die "the \"$NOTE_NAME\" Notes body is not a single JWT-shaped Attic token"
  payload=${token#*.}
  payload=${payload%%.*}
  printf '%s' "$payload" | jq -Rse '
    gsub("-"; "+") | gsub("_"; "/") |
    . + ("==="[0:((4 - (length % 4)) % 4)]) |
    @base64d | fromjson | type == "object"
  ' >/dev/null 2>&1 || die "the \"$NOTE_NAME\" Notes body is not a well-formed JWT"

  netrc_line=$(printf 'machine %s login attic password %s' "$NETRC_MACHINE" "$token") \
    || die 'could not prepare the netrc entry'
  install_netrc "$netrc_line"

  printf 'Installed the Attic reader credential for %s at %s (root:root, mode 0600).\n' \
    "$NETRC_MACHINE" "$NETRC_PATH"
}

case "${1:-setup}" in
  setup)
    [ "$#" -le 1 ] || die 'setup takes no arguments'
    attic_setup
    ;;
  bw-config)
    [ "$#" -eq 1 ] || die 'bw-config takes no arguments'
    bw_config
    ;;
  bw-login)
    [ "$#" -eq 1 ] || die 'bw-login takes no arguments'
    bw_login
    ;;
  *)
    die 'unknown command (expected setup, bw-config, or bw-login)'
    ;;
esac
