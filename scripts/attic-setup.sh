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
# ATTIC_SETUP_ETC_DIR moves the install destination so the privileged stage can
# be exercised against a disposable fixture. A real `sudo` invocation drops it
# under the default environment reset; the default is /etc/nix.
set -eu

NOTE_NAME='NixOS Attic Pull Token'
NETRC_MACHINE='attic.panic.ac'
BW_SERVER='https://vault.panic.ac'
etc_dir=${ATTIC_SETUP_ETC_DIR:-/etc/nix}
netrc_path="$etc_dir/attic.netrc"

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
  [ -d "$etc_dir" ] || die "destination directory $etc_dir does not exist"
  [ ! -L "$netrc_path" ] || die "refusing to replace the symlink at $netrc_path"
  if [ -e "$netrc_path" ]; then
    [ -f "$netrc_path" ] || die "refusing to replace the non-regular file $netrc_path"
    [ -r "$netrc_path" ] || die "cannot read the existing file at $netrc_path"
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
    ' "$netrc_path") || die "cannot read the existing file at $netrc_path"
    [ -z "$entries" ] || die "refusing to overwrite $netrc_path: it names another netrc entry"
  fi

  umask 077
  tmp=$(mktemp "$etc_dir/.attic.netrc.XXXXXX") || die "cannot create a temporary file in $etc_dir"
  trap 'rm -f -- "$tmp"' EXIT
  cat > "$tmp"
  [ -s "$tmp" ] || die 'no credential was provided on stdin'
  [ "$(grep -c '' "$tmp")" -eq 1 ] || die 'the credential is not a single netrc entry'
  grep -Eq '^machine attic\.panic\.ac password [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' "$tmp" \
    || die 'the credential is not the expected Attic netrc entry'
  chmod 0600 "$tmp" || die "cannot set the mode of the temporary file in $etc_dir"
  if [ "$(id -u)" -eq 0 ]; then
    chown root:root "$tmp" || die "cannot set the owner of the temporary file in $etc_dir"
  fi
  mv -f -- "$tmp" "$netrc_path" || die "cannot replace $netrc_path"
  tmp=''
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

  netrc_line=$(printf 'machine %s password %s' "$NETRC_MACHINE" "$token") \
    || die 'could not prepare the netrc entry'
  script_path=$(readlink -f -- "$0") || die 'could not resolve this script path'
  sudo_flags=()
  [ -t 0 ] || sudo_flags=(-n)
  printf '%s\n' "$netrc_line" \
    | sudo "${sudo_flags[@]}" env -u BW_SESSION -- "$script_path" --install-netrc \
    || die 'installing the credential failed; the previous file was left unchanged (run from an interactive terminal if sudo needs a password)'

  printf 'Installed the Attic reader credential for %s at %s (root:root, mode 0600).\n' \
    "$NETRC_MACHINE" "$netrc_path"
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
  --install-netrc)
    [ "$#" -eq 1 ] || die 'the install stage takes no arguments'
    install_netrc
    ;;
  *)
    die 'unknown command (expected setup, bw-config, bw-login, or --install-netrc)'
    ;;
esac
