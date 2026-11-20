#!/usr/bin/env bash
# Install the Attic reader credential for the Nix daemon from Bitwarden.
#
# The Bitwarden item is a secure note named "NixOS Attic Pull Token". Its Notes
# body is one raw Attic pull token (a JWT). The token is installed as the only
# entry in /etc/nix/attic.netrc, owned by root with mode 0600, so the Nix daemon
# can read the private cache without per-command flags.
#
# ATTIC_SETUP_ETC_DIR moves the install destination so the privileged stage can
# be exercised against a disposable fixture. A real `sudo` invocation drops it
# under the default environment reset; the default is /etc/nix.
set -eu

NOTE_NAME='NixOS Attic Pull Token'
NETRC_MACHINE='attic.panic.ac'
etc_dir=${ATTIC_SETUP_ETC_DIR:-/etc/nix}
netrc_path="$etc_dir/attic.netrc"

die() {
  printf 'attic-setup: %s\n' "$*" >&2
  exit 1
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

main() {
  command -v bw >/dev/null 2>&1 || die 'the Bitwarden CLI (bw) is not on PATH'
  command -v jq >/dev/null 2>&1 || die 'jq is not on PATH'
  command -v sudo >/dev/null 2>&1 || die 'sudo is not on PATH'

  status=$(bw status 2>/dev/null) || die 'could not read Bitwarden status; run "bw login" and try again'
  [ "$(printf '%s' "$status" | jq -r '.status // empty' 2>/dev/null)" = 'unlocked' ] \
    || die 'Bitwarden is not unlocked; run "bw unlock" and export BW_SESSION before this task'

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

if [ "${1:-}" = '--install-netrc' ]; then
  [ "$#" -eq 1 ] || die 'the install stage takes no arguments'
  install_netrc
else
  [ "$#" -eq 0 ] || die 'this task takes no arguments'
  main
fi
