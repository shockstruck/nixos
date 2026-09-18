#!@bash@
# Direct-launch shim for OGI-managed Steam shortcuts. Installed as
# $out/bin/opengameinstaller-steam-launch by packages/opengameinstaller.nix,
# which points the opengameinstaller wrapper's APPIMAGE at this binary
# instead of at itself. Every claim below cites Nat3z/OpenGameInstaller
# (application/src/electron/...) at tag v4.3.1, verified directly against
# that tag's source, not against the original design research.
#
# Why this exists: OGI's Steam-shortcut writer takes the shortcut's launcher
# path from $APPIMAGE verbatim (handlers/helpers.app/platform.ts:44-47,
# getOgiExecutablePath) and writes LaunchOptions as
# "<APPIMAGE>" --game-id=N --no-sandbox -- %command%
# (handlers/helpers.app/steam.ts:308, upsertShortcut call at :318-345).
# Normally Steam then starts the whole Electron app just to have it turn
# around, reconstruct the game's own launch chain from
# library/<id>.json, and spawn it (handlers/handler.library.ts
# executeWrapperCommandForAppSteam, :565-724) — paying Electron's startup
# cost on every single game launch. This shim reproduces that
# reconstruction directly in shell and execs the result, no Electron
# involved.
#
# Kevin's decision on the parent issue: addon pre/post launch hooks are
# dropped — a hook-only invocation is a silent no-op (step 2 below).
set -euo pipefail

ogi_forward() {
  exec /run/current-system/sw/bin/opengameinstaller "$@"
}

# --- Step 1: forwarding mode -------------------------------------------
# getOgiExecutablePath() (platform.ts:44-47) is also the path OGI's
# desktop-shortcut writer and its own "Add non-Steam game" flow use, and
# those invocations never carry a game-id/`--`-separated launch chain
# (single-instance-launch.ts:56-67 parseGameIdArg, :74-90
# parseWrapperAfterSeparator). Anything shaped unlike a Steam-managed
# launch must still reach the real Electron app.
args=("$@")
argc=$#

game_id=""
for a in "${args[@]}"; do
  case "$a" in
    --game-id=*) game_id="${a#--game-id=}" ;;
  esac
done

sep_index=-1
i=0
for a in "${args[@]}"; do
  if [[ "$a" == "--" ]]; then
    sep_index=$i
    break
  fi
  i=$((i + 1))
done

if [[ -z "$game_id" ]] || (( sep_index == -1 )) || (( sep_index >= argc - 1 )); then
  ogi_forward "$@"
fi

# --- Step 2: hook-only invocations --------------------------------------
# parseLaunchHookArgs (single-instance-launch.ts:75-85) recognizes exactly
# these three flags; any of them present means this call is an addon
# pre/post hook or a "don't launch" probe, not the actual game launch.
for a in "${args[@]}"; do
  case "$a" in
    --no-launch | --pre | --post) exit 0 ;;
  esac
done

steam_chain=("${args[@]:$((sep_index + 1))}")

# --- Step 3: read the library entry -------------------------------------
# getLibraryPath (helpers.app/library.ts:14) joins __dirname with
# library/<id>.json; __dirname is $OGI_DIRECTORY when set, else
# ~/.local/share/OpenGameInstaller (manager/manager.paths.ts).
ogi_dir="${OGI_DIRECTORY:-$HOME/.local/share/OpenGameInstaller}"
library_json="$ogi_dir/library/${game_id}.json"

if [[ ! -f "$library_json" ]]; then
  echo "opengameinstaller-steam-launch: no library entry at $library_json for game $game_id" >&2
  exit 1
fi

launch_executable="$(@jq@ -r '.launchExecutable // ""' "$library_json")"
cwd="$(@jq@ -r '.cwd // ""' "$library_json")"
launch_arguments="$(@jq@ -r '.launchArguments // ""' "$library_json")"
has_umu="$(@jq@ -r 'if .umu then "1" else "0" end' "$library_json")"
umu_id="$(@jq@ -r '.umu.umuId // ""' "$library_json")"
umu_wineprefix="$(@jq@ -r '.umu.winePrefixPath // ""' "$library_json")"
mapfile -t umu_dll_overrides_raw < <(@jq@ -r '(.umu.dllOverrides // []) | .[]' "$library_json")

# --- Step 4: tokenise launchArguments -----------------------------------
# Same matched-substring/dequote behaviour as parseLaunchArgumentTokens
# (lib/launch-command.ts:17-30): a token is a maximal run of
# [^\s"']/quoted spans with no intervening whitespace; only when a whole
# token starts AND ends with the same quote character are that one
# leading and trailing character stripped (embedded quotes elsewhere in
# the token are left alone, matching upstream exactly). An unterminated
# quote cannot be part of any alternative of the upstream regex and is
# dropped here too, rather than approximated.
tokenize_launch_arguments() {
  local input="$1"
  local len=${#input}
  local i=0 c current="" in_token=0
  TOKENS=()
  while (( i < len )); do
    c="${input:i:1}"
    case "$c" in
      ' ' | $'\t' | $'\n' | $'\r')
        if (( in_token )); then
          TOKENS+=("$current")
          current=""
          in_token=0
        fi
        i=$((i + 1))
        ;;
      '"' | "'")
        local quote="$c" j start
        j=$((i + 1))
        start=$j
        while (( j < len )) && [[ "${input:j:1}" != "$quote" ]]; do
          j=$((j + 1))
        done
        if (( j < len )); then
          current+="${quote}${input:start:$((j - start))}${quote}"
          in_token=1
          i=$((j + 1))
        else
          # Unterminated quote: not matched by the upstream regex either.
          if (( in_token )); then
            TOKENS+=("$current")
            current=""
            in_token=0
          fi
          i=$len
        fi
        ;;
      *)
        current+="$c"
        in_token=1
        i=$((i + 1))
        ;;
    esac
  done
  if (( in_token )); then
    TOKENS+=("$current")
  fi
}

dequote_token() {
  local t="$1" len=${#1}
  if (( len >= 2 )); then
    if [[ "${t:0:1}" == '"' && "${t: -1}" == '"' ]] \
      || [[ "${t:0:1}" == "'" && "${t: -1}" == "'" ]]; then
      printf '%s' "${t:1:$((len - 2))}"
      return
    fi
  fi
  printf '%s' "$t"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

tokenize_launch_arguments "$launch_arguments"
dequoted=()
for t in "${TOKENS[@]}"; do
  dequoted+=("$(dequote_token "$t")")
done

# --- Step 5: environment overlay ----------------------------------------
# Order mirrors handler.library.ts's executeWrapperCommandForAppSteam
# (:704-722): inherited env (already ours from Steam) < effectiveLaunchEnv
# < PROTON_LOG=1 < (if umu) STEAM_COMPAT_DATA_PATH/WINEPREFIX < (if umu and
# non-empty) WINEDLLOVERRIDES.
#
# effectiveLaunchEnv itself (handler.umu.ts:253-274 getEffectiveLaunchEnv)
# is: leading key=value tokens of launchArguments (stripLeadingLaunchEnvTokens,
# handler.umu.ts:98-107, any key) overridden by every key of the library
# entry's launchEnv object; a PROTONPATH whose trimmed lower-case value is
# "umu-proton" is dropped (handler.umu.ts:109-117 normalizeProtonPathValue).
leading_count=0
declare -A leading_env=()
for t in "${dequoted[@]}"; do
  if [[ "$t" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    leading_env["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    leading_count=$((leading_count + 1))
  else
    break
  fi
done

declare -A effective_env=()
for k in "${!leading_env[@]}"; do
  effective_env["$k"]="${leading_env[$k]}"
done
# NUL-delimited rather than @tsv: @tsv backslash-escapes \, tab and
# newline, which would double every backslash in a value — and upstream's
# parseDllOverridesValue explicitly expects backslash-escaped quotes in a
# WINEDLLOVERRIDES value (handler.umu.ts:194-198). Keys are trimmed and
# null values skipped as in getEffectiveLaunchEnv (handler.umu.ts:264-267).
while IFS= read -r -d '' k && IFS= read -r -d '' v; do
  k="$(trim "$k")"
  [[ -n "$k" ]] && effective_env["$k"]="$v"
done < <(@jq@ -j '(.launchEnv // {}) | to_entries[] | select(.value != null) | "\(.key)\u0000\(.value | tostring)\u0000"' "$library_json")

if [[ -n "${effective_env[PROTONPATH]+x}" ]]; then
  pp_trimmed="$(trim "${effective_env[PROTONPATH]}")"
  pp_lower="${pp_trimmed,,}"
  if [[ -z "$pp_trimmed" || "$pp_lower" == "umu-proton" ]]; then
    unset 'effective_env[PROTONPATH]'
  else
    effective_env[PROTONPATH]="$pp_trimmed"
  fi
fi

for k in "${!effective_env[@]}"; do
  export "$k=${effective_env[$k]}"
done
export PROTON_LOG=1

# --- known launch-env keys stripped from the rewritten argv (below) -----
# handler.umu.ts:69-76 KNOWN_LAUNCH_ENV_VARS.
is_known_launch_env_assignment() {
  local t="$1"
  [[ "$t" == *=* ]] || return 1
  local key="${t%%=*}"
  [[ -n "$key" ]] || return 1
  case "$key" in
    WINEPREFIX | WINEDLLOVERRIDES | STEAM_COMPAT_DATA_PATH | PROTONPATH | GAMEID | STORE) return 0 ;;
    *) return 1 ;;
  esac
}

remaining=("${dequoted[@]:$leading_count}")
filtered=()
for t in "${remaining[@]}"; do
  if is_known_launch_env_assignment "$t"; then
    continue
  fi
  filtered+=("$t")
done

cmd_index=-1
for idx in "${!filtered[@]}"; do
  if [[ "${filtered[idx]}" == "%command%" ]]; then
    cmd_index=$idx
    break
  fi
done

effective_args=()
if (( cmd_index >= 0 )); then
  for ((idx = cmd_index + 1; idx < ${#filtered[@]}; idx++)); do
    [[ "${filtered[idx]}" == "%command%" ]] && continue
    effective_args+=("${filtered[idx]}")
  done
else
  effective_args=("${filtered[@]}")
fi

# --- DLL overrides (only meaningful for a umu game) ---------------------
# handler.umu.ts:196-224 parseDllOverridesValue, :226-233
# inferDllOverridesFromLaunchArguments/Env, :236-245
# getEffectiveDllOverrides (dedup via uniqueCaseInsensitive, first
# occurrence wins), :328-347 buildDllOverrides.
strip_dll_name_quotes() {
  local s="$1"
  if [[ "$s" == '\"'* || "$s" == "\\'"* ]]; then
    s="${s:2}"
  elif [[ "$s" == '"'* || "$s" == "'"* ]]; then
    s="${s:1}"
  fi
  if [[ "$s" == *'\"' || "$s" == *"\\'" ]]; then
    s="${s:0:$((${#s} - 2))}"
  elif [[ "$s" == *'"' || "$s" == *"'" ]]; then
    s="${s:0:$((${#s} - 1))}"
  fi
  printf '%s' "$s"
}

parse_dll_overrides_value() {
  local raw="$1"
  local trimmed unquoted normalized ulen tlen
  trimmed="$(trim "$raw")"
  [[ -n "$trimmed" ]] || return 0
  unquoted="$trimmed"
  tlen=${#trimmed}
  if (( tlen >= 2 )); then
    if [[ "${trimmed:0:1}" == '"' && "${trimmed: -1}" == '"' ]] \
      || [[ "${trimmed:0:1}" == "'" && "${trimmed: -1}" == "'" ]]; then
      unquoted="${trimmed:1:$((tlen - 2))}"
    fi
  fi
  normalized="$unquoted"
  ulen=${#unquoted}
  if (( ulen >= 4 )); then
    if [[ "${unquoted:0:2}" == '\"' && "${unquoted: -2}" == '\"' ]] \
      || [[ "${unquoted:0:2}" == "\\'" && "${unquoted: -2}" == "\\'" ]]; then
      normalized="${unquoted:2:$((ulen - 4))}"
    fi
  fi
  local seg s left value name
  local -a dll_segments dll_names
  IFS=';' read -ra dll_segments <<<"$normalized"
  for seg in "${dll_segments[@]}"; do
    s="$(trim "$seg")"
    [[ -n "$s" ]] || continue
    if [[ "$s" == *=* ]]; then
      left="$(trim "${s%%=*}")"
      value="$(trim "${s#*=}")"
      [[ -n "$left" ]] || continue
      IFS=',' read -ra dll_names <<<"$left"
      for name in "${dll_names[@]}"; do
        name="$(strip_dll_name_quotes "$(trim "$name")")"
        [[ -n "$name" ]] || continue
        printf '%s\n' "${name}=${value}"
      done
    else
      name="$(strip_dll_name_quotes "$s")"
      [[ -n "$name" ]] || continue
      printf '%s\n' "$name"
    fi
  done
}

unique_case_insensitive() {
  local -A seen=()
  local v t lower
  for v in "$@"; do
    t="$(trim "$v")"
    [[ -n "$t" ]] || continue
    lower="${t,,}"
    [[ -n "${seen[$lower]+x}" ]] && continue
    seen["$lower"]=1
    printf '%s\n' "$t"
  done
}

build_dll_overrides() {
  local entry dll_part value base lower out=()
  for entry in "$@"; do
    if [[ "$entry" == *=* ]]; then
      dll_part="${entry%%=*}"
      value="$(trim "${entry#*=}")"
    else
      dll_part="$entry"
      value=""
    fi
    dll_part="$(trim "$dll_part")"
    base="${dll_part##*/}"
    lower="${base,,}"
    if [[ "$lower" == *.dll ]]; then
      base="${base:0:$((${#base} - 4))}"
    fi
    [[ -n "$base" ]] || continue
    if [[ -n "$value" ]]; then
      out+=("${base}=${value}")
    else
      out+=("${base}=n,b")
    fi
  done
  local IFS=';'
  printf '%s' "${out[*]:-}"
}

wine_prefix=""
if [[ "$has_umu" == "1" ]]; then
  # handler.umu.ts:398-406 convertUmuId, :408-411 getUmuWinePrefix,
  # :413-421 getLibraryUmuWinePrefix.
  if [[ -n "$umu_wineprefix" ]]; then
    wine_prefix="$umu_wineprefix"
  else
    id_clean="$umu_id"
    id_clean="${id_clean#steam:}"
    id_clean="${id_clean#umu:}"
    wine_prefix="$HOME/.ogi-wine-prefixes/umu-${id_clean}"
  fi
  export STEAM_COMPAT_DATA_PATH="$wine_prefix"
  export WINEPREFIX="$wine_prefix"

  from_args=""
  for t in "${dequoted[@]}"; do
    if [[ "$t" == "WINEDLLOVERRIDES="* ]]; then
      from_args="${t#WINEDLLOVERRIDES=}"
      break
    fi
  done

  mapfile -t dll_from_args < <(parse_dll_overrides_value "$from_args")
  dll_from_env=()
  if [[ -n "${effective_env[WINEDLLOVERRIDES]+x}" ]]; then
    mapfile -t dll_from_env < <(parse_dll_overrides_value "${effective_env[WINEDLLOVERRIDES]}")
  fi
  mapfile -t dll_combined < <(unique_case_insensitive \
    "${umu_dll_overrides_raw[@]:-}" "${dll_from_args[@]:-}" "${dll_from_env[@]:-}")

  if [[ ${#dll_combined[@]} -gt 0 ]]; then
    wine_dll_overrides="$(build_dll_overrides "${dll_combined[@]}")"
    [[ -n "$wine_dll_overrides" ]] && export WINEDLLOVERRIDES="$wine_dll_overrides"
  fi
fi

# --- Step 6: command rewrite --------------------------------------------
# handler.library.ts:586-661 (verb/collapsed-launcher detection,
# :617-666 split-Proton token normalisation) and :668-701 (fixedArgs/
# wrappedCommand/wrappedArgv). We already hold Steam's chain as argv, so
# the split-Proton workaround at :617-666 — needed only because OGI
# re-quotes the chain into a string and re-parses it with shell-quote —
# does not apply here.
wfear_index=-1
for idx in "${!steam_chain[@]}"; do
  if [[ "${steam_chain[idx]}" == "waitforexitandrun" ]]; then
    wfear_index=$idx
    break
  fi
done

if (( wfear_index >= 0 )); then
  fixed=("${steam_chain[@]:0:$((wfear_index + 1))}")
else
  last_dash_index=-1
  for idx in "${!steam_chain[@]}"; do
    if [[ "${steam_chain[idx]}" == "--" ]]; then
      last_dash_index=$idx
    fi
  done
  if (( last_dash_index >= 0 )); then
    fixed=("${steam_chain[@]:0:$((last_dash_index + 1))}")
  else
    fixed=("${steam_chain[@]}")
  fi
fi

game_command="${steam_chain[0]}"
final_argv=("${fixed[@]:1}" "$launch_executable" "${effective_args[@]}")

# --- Step 7: run it -------------------------------------------------------
# systemd-cat's own argv parsing stops at the first non-option word
# (systemd/src/journal/cat.c parse_argv), so only "-t
# opengameinstaller-steam-launch --stderr-priority=warning" are consumed
# as its options; the game's command and argv pass through untouched.
if [[ -n "$cwd" ]]; then
  cd "$cwd"
fi

exec @systemdcat@ -t opengameinstaller-steam-launch --stderr-priority=warning \
  "$game_command" "${final_argv[@]}"
