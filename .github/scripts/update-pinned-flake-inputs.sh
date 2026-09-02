#!/usr/bin/env bash
#
# Bump every flake input that is pinned to an explicit release tag to the newest
# version its upstream has published.
#
# Why this exists: `nix flake update` re-locks each input against the ref that
# is written in flake.nix. An input pinned to `github:owner/repo/v1.2.3`
# therefore stays on v1.2.3 forever, no matter how often the lock is refreshed.
# Only flake.nix itself moving forward can pick up a new release. This rewrites
# those refs so the scheduled lock job locks the new version in the same PR.
#
# Left alone deliberately:
#   * inputs with no ref            (github:owner/repo)      — already floating
#   * inputs pinned to a branch     (github:nixos/nixpkgs/nixos-unstable)
#   * inputs pinned to a commit SHA (not a version tag)
#   * non-github: URLs
# `nix flake update` already tracks the first two, and a SHA pin is a
# deliberate freeze.
#
# A pin that is itself a prerelease (v5.0.0-beta.9) may advance to either a
# newer prerelease or the stable release that supersedes it. A pin that is a
# stable release never advances to a prerelease.
#
# Usage: update-pinned-flake-inputs.sh [path/to/flake.nix]
# Requires: gh, authenticated via GH_TOKEN.

set -euo pipefail

flake="${1:-flake.nix}"

if [[ ! -f $flake ]]; then
  echo "error: no such file: $flake" >&2
  exit 1
fi

# A ref we are willing to move: optional v, a numeric core, optional
# prerelease suffix. Anything else (branch names, SHAs) is not touched.
version_re='^v?[0-9]+(\.[0-9]+)*(-[0-9A-Za-z][0-9A-Za-z.]*)?$'

is_prerelease() { [[ $1 =~ ^v?[0-9]+(\.[0-9]+)*- ]]; }

# GNU `sort -V` orders "5.0.0" before "5.0.0-beta.9", which is backwards for
# semver. It orders "~" before everything, so swapping the prerelease separator
# gives the correct precedence.
sortable() { printf '%s' "${1/-/\~}"; }

# Echoes the greater of two version strings.
newest() {
  local a="$1" b="$2" winner
  winner="$(printf '%s\t%s\n%s\t%s\n' "$(sortable "$a")" "$a" "$(sortable "$b")" "$b" |
    sort -V -k1,1 | tail -n1 | cut -f2)"
  printf '%s' "$winner"
}

# Candidate tags for owner/repo, newest first is not assumed — the caller picks
# the maximum. Published releases are preferred; repos that tag without cutting
# releases fall back to plain git tags.
candidates() {
  local owner="$1" repo="$2" allow_pre="$3" line tag pre
  local -a out=()

  while IFS=$'\t' read -r tag pre; do
    [[ -n $tag ]] || continue
    [[ $tag =~ $version_re ]] || continue
    if [[ $allow_pre == false ]] && { [[ $pre == true ]] || is_prerelease "$tag"; }; then
      continue
    fi
    out+=("$tag")
  done < <(gh api "repos/${owner}/${repo}/releases?per_page=100" \
    --jq '.[] | select(.draft | not) | [.tag_name, (.prerelease | tostring)] | @tsv' 2>/dev/null || true)

  if [[ ${#out[@]} -eq 0 ]]; then
    while read -r line; do
      [[ -n $line ]] || continue
      [[ $line =~ $version_re ]] || continue
      if [[ $allow_pre == false ]] && is_prerelease "$line"; then
        continue
      fi
      out+=("$line")
    done < <(gh api "repos/${owner}/${repo}/tags?per_page=100" --jq '.[].name' 2>/dev/null || true)
  fi

  [[ ${#out[@]} -eq 0 ]] || printf '%s\n' "${out[@]}"
}

content="$(cat "$flake")"
bumped=0
summary=""

# Matches:  <name>.url = "github:<owner>/<repo>/<ref>";
url_re='^[[:space:]]*([A-Za-z0-9_.-]+)\.url[[:space:]]*=[[:space:]]*"github:([^/"]+)/([^/"]+)/([^"]+)"[[:space:]]*;'

while IFS= read -r line; do
  [[ $line =~ $url_re ]] || continue

  input="${BASH_REMATCH[1]}"
  owner="${BASH_REMATCH[2]}"
  repo="${BASH_REMATCH[3]}"
  ref="${BASH_REMATCH[4]}"

  if [[ ! $ref =~ $version_re ]]; then
    echo "skip  ${input}: ref '${ref}' is not a version tag"
    continue
  fi

  allow_pre=false
  if is_prerelease "$ref"; then
    allow_pre=true
  fi

  best=""
  while read -r tag; do
    [[ -n $tag ]] || continue
    if [[ -z $best ]]; then
      best="$tag"
    else
      best="$(newest "$best" "$tag")"
    fi
  done < <(candidates "$owner" "$repo" "$allow_pre")

  if [[ -z $best ]]; then
    echo "warn  ${input}: no candidate releases or tags found for ${owner}/${repo}" >&2
    continue
  fi

  if [[ $best == "$ref" ]] || [[ "$(newest "$ref" "$best")" == "$ref" ]]; then
    echo "ok    ${input}: ${ref} is current (newest upstream: ${best})"
    continue
  fi

  echo "bump  ${input}: ${ref} -> ${best}"
  content="${content//"\"github:${owner}/${repo}/${ref}\""/"\"github:${owner}/${repo}/${best}\""}"
  if [[ -z $summary ]]; then
    summary="### Pinned inputs bumped to their latest release"$'\n\n'
  fi
  summary+="- \`${input}\`: \`${ref}\` → \`${best}\`"$'\n'
  bumped=$((bumped + 1))
done <"$flake"

if [[ $bumped -gt 0 ]]; then
  printf '%s\n' "$content" >"$flake"
fi

echo "bumped ${bumped} pinned input(s)"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    echo "bumped=${bumped}"
    echo "summary<<PINNED_EOF"
    printf '%s' "$summary"
    echo "PINNED_EOF"
  } >>"$GITHUB_OUTPUT"
fi
