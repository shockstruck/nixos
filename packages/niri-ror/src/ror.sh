#!/bin/bash
# Unified run-or-raise script for niri
# Usage:
#   ./ror.sh --app-id <id> --title <title> --operation intersection -- command...
#   ./ror.sh --app-id <id> --command "gio launch /path/to/app.desktop"

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
log_file="${ROR_LOG_FILE:-/tmp/ror.log}"
jq_lib_dir="$script_dir/lib"
jq_filter_file=""
jq_filter_tmp=""
log_enabled="false"
notify_enabled="false"
elapsed_ms=0
trace_enabled="false"
json_tmp=""
filtered_tmp=""
notify_cmd_spec=${ROR_NOTIFY_CMD:-'notify-send -a "ror" -t 300'}
notify_cmd=()

app_id=""
title=""
app_id_regex=""
title_regex=""
command_str=""
declare -a command_args=()
app_name=""
cwd=""
operation=""
exclude_focused="false"
printdebug="false"
list_only="false"
time_run="false"

cleanup() {
  if [[ -n "${jq_filter_tmp:-}" && -f "$jq_filter_tmp" ]]; then
    rm -f "$jq_filter_tmp"
  fi
  if [[ -n "${json_tmp:-}" && -f "$json_tmp" ]]; then
    rm -f "$json_tmp"
  fi
  if [[ -n "${filtered_tmp:-}" && -f "$filtered_tmp" && "$filtered_tmp" != "${json_tmp:-}" ]]; then
    rm -f "$filtered_tmp"
  fi
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: ror.sh [options] -- command...
       ror.sh [options] --command "<command string>"

Options:
  --app-id <id>           Window app_id substring to match (contains).
  --title <title>         Substring to match in window title.
  --app-id-regex <re>     Regex to match app_id (takes precedence over --app-id).
  --title-regex <re>      Regex to match title (takes precedence over --title).
  --operation <op>        union (either), intersection (both), difference (app_id minus title), or (first non-empty). Default: intersection when both app-id and title are present, else best effort.
  --app-name <name>       Friendly name for notifications (defaults to app-id/title).
  --cwd <path>            Working directory for the command.
  --exclude-focused       Exclude currently focused window from cycling.
  --printdebug            Print filtered results to stderr via jq debug.
  --list                  Print filtered window list and exit (no focus/launch).
  --time                  Log elapsed time (ms) for search/launch; prints when debug/listing.
  --jq-filter-file <f>    jq filter file to pre-process window JSON before ws.jq.
  --jq-filter '<expr>'    Inline jq filter (written to a temp file) applied before ws.jq.
  --log                   Enable file logging (default: off). Uses $ROR_LOG_FILE (/tmp/ror.log).
  --notify                Enable desktop notifications (default: off).
  --trace                 Enable bash xtrace for debugging this script.
  --command "<string>"    Command string (word-split) to run if no match is found.
  --help                  Show this help.

Command:
  Pass the command either as a string via --command, or after a literal -- so
  it is preserved as-is: ror.sh ... -- gio launch /path/app.desktop
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

if [[ -n "$notify_cmd_spec" ]]; then
  # shellcheck disable=SC2086
  eval "notify_cmd=($notify_cmd_spec)" || notify_cmd=()
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
  --app-id)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --app-id" >&2
      exit 1
    }
    app_id="$2"
    shift 2
    ;;
  --title)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --title" >&2
      exit 1
    }
    title="$2"
    shift 2
    ;;
  --app-id-regex)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --app-id-regex" >&2
      exit 1
    }
    app_id_regex="$2"
    shift 2
    ;;
  --title-regex)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --title-regex" >&2
      exit 1
    }
    title_regex="$2"
    shift 2
    ;;
  --command)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --command" >&2
      exit 1
    }
    command_str="$2"
    shift 2
    ;;
  --app-name)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --app-name" >&2
      exit 1
    }
    app_name="$2"
    shift 2
    ;;
  --cwd)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --cwd" >&2
      exit 1
    }
    cwd="$2"
    shift 2
    ;;
  --operation)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --operation" >&2
      exit 1
    }
    operation="$2"
    shift 2
    ;;
  --exclude-focused)
    exclude_focused="true"
    shift
    ;;
  --printdebug)
    printdebug="true"
    shift
    ;;
  --list)
    list_only="true"
    shift
    ;;
  --time)
    time_run="true"
    shift
    ;;
  --jq-filter-file)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --jq-filter-file" >&2
      exit 1
    }
    if [[ -n "$jq_filter_file" ]]; then
      echo "Only one jq filter may be provided" >&2
      exit 1
    fi
    jq_filter_file="$2"
    shift 2
    ;;
  --jq-filter)
    [[ $# -lt 2 ]] && {
      echo "Missing value for --jq-filter" >&2
      exit 1
    }
    if [[ -n "$jq_filter_file" ]]; then
      echo "Only one jq filter may be provided" >&2
      exit 1
    fi
    jq_filter_tmp="$(mktemp)"
    printf '%s\n' "$2" >"$jq_filter_tmp"
    jq_filter_file="$jq_filter_tmp"
    shift 2
    ;;
  --log)
    log_enabled="true"
    shift
    ;;
  --notify)
    notify_enabled="true"
    shift
    ;;
  --trace)
    trace_enabled="true"
    shift
    ;;
  --help)
    usage
    exit 0
    ;;
  --)
    shift
    command_args=("$@")
    break
    ;;
  *)
    echo "Unknown parameter: $1" >&2
    usage
    exit 1
    ;;
  esac
done

if [[ ${#command_args[@]} -eq 0 && -n "$command_str" ]]; then
  # shellcheck disable=SC2206
  command_args=($command_str)
fi

if [[ ${#command_args[@]} -eq 0 ]]; then
  echo "Error: command to launch is required (use --command or pass after --)" >&2
  exit 1
fi

if [[ "$trace_enabled" == "true" ]]; then
  set -x
fi

if [[ -n "$jq_filter_file" && ! -f "$jq_filter_file" ]]; then
  echo "Error: jq filter file not found: $jq_filter_file" >&2
  exit 1
fi

if [[ -z "$app_name" ]]; then
  if [[ -n "$app_id" ]]; then
    app_name="$app_id"
  elif [[ -n "$title" ]]; then
    app_name="$title"
  else
    app_name="Application"
  fi
fi

log() {
  [[ "$log_enabled" != "true" ]] && return
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$log_file"
}

notify() {
  if [[ "$notify_enabled" != "true" ]]; then
    return
  fi
  if [[ ${#notify_cmd[@]} -eq 0 ]]; then
    return
  fi
  if [[ $# -eq 2 ]]; then
    "${notify_cmd[@]}" "$1" "$2"
  else
    "${notify_cmd[@]}" "$1"
  fi
}

log_action() {
  local msg="$1"
  if [[ "$time_run" == "true" ]]; then
    msg="$msg elapsed_ms=$elapsed_ms"
  fi
  log "$msg"
}

launch() {
  notify "Starting $app_name"
  if [[ -n "$cwd" ]]; then
    cd "$cwd" || exit
  fi
  log_action "Launching: ${command_args[*]} (cwd=${cwd:-.})"
  "${command_args[@]}" &
}

search() {
  jq_args=(--arg app_id "$app_id" --arg title "$title" --arg app_id_regex "$app_id_regex" --arg title_regex "$title_regex" --arg exclude_focused "$exclude_focused" --arg operation "$operation" --arg printdebug "$printdebug" --arg list_only "$list_only")

  json_tmp="$(mktemp)"
  if ! niri msg -j windows >"$json_tmp"; then
    echo >&2 "Failed to fetch windows via niri"
    exit 1
  fi

  start_ns=$(date +%s%N)

  if [[ -n "$jq_filter_file" ]]; then
    filtered_tmp="$(mktemp)"
    set +e
    jq -L "$jq_lib_dir" -L "$script_dir" -f "$jq_filter_file" <"$json_tmp" >"$filtered_tmp"
    jq_status=$?
    set -e
    if [[ $jq_status -ne 0 ]]; then
      echo >&2 "jq pre-filter failed (status=$jq_status). Input from niri follows:"
      sed >&2 -n '1,200p' "$json_tmp"
      exit $jq_status
    fi
    original_json="$json_tmp"
    json_tmp="$filtered_tmp"
    rm -f "$original_json"
  fi

  set +e
  winid=$(jq -L "$jq_lib_dir" -L "$script_dir" -f "$script_dir/ws.jq" "${jq_args[@]}" <"$json_tmp")
  jq_status=$?
  set -e
  if [[ $jq_status -ne 0 ]]; then
    echo >&2 "jq failed (status=$jq_status). Input from niri follows:"
    sed >&2 -n '1,200p' "$json_tmp"
    exit $jq_status
  fi
  end_ns=$(date +%s%N)
  elapsed_ms=$(((end_ns - start_ns) / 1000000))

  log_action "Search result winid:${winid:-null}"
  if [[ "$time_run" == "true" || "$printdebug" == "true" || "$list_only" == "true" ]]; then
    echo >&2 "elapsed_ms=${elapsed_ms}"
  fi

  if [[ "$list_only" == "true" ]]; then
    printf '%s\n' "$winid"
    exit 0
  fi

  if [[ "$winid" == "null" || -z "$winid" ]]; then
    launch
  else
    log_action "Focusing winid: $winid"
    notify "Found $app_name" "Raising window..."
    niri msg action focus-window --id "$winid"
  fi
}

search
