{ pkgs, ... }:
let
  bw-ssh-pull = pkgs.writeShellApplication {
    name = "bw-ssh-pull";
    runtimeInputs = with pkgs; [
      bitwarden-cli
      coreutils
      jq
      openssh
    ];
    text = ''
      server="''${BW_SERVER:-https://vault.panic.ac}"
      server="''${server%/}"
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/bitwarden"
      config_file="$config_dir/ssh-keys"
      ssh_dir="$HOME/.ssh"

      usage() {
        cat <<'EOF'
      Usage:
        bw-ssh-pull configure UUID=FILENAME [UUID=FILENAME ...]
        bw-ssh-pull [pull] [UUID=FILENAME ...]

      With no UUID arguments, pull reads ~/.config/bitwarden/ssh-keys.
      SSH Key items are read directly; Secure Note bodies are decoded as base64.
      EOF
      }

      validate_spec() {
        local spec="$1"
        if [[ ! "$spec" =~ ^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})=([A-Za-z0-9][A-Za-z0-9._-]*)$ ]]; then
          printf 'Invalid key mapping: %s (expected UUID=FILENAME)\n' "$spec" >&2
          return 1
        fi
      }

      configure() {
        local specs=("$@")
        if (( ''${#specs[@]} == 0 )); then
          usage >&2
          exit 2
        fi
        for spec in "''${specs[@]}"; do
          validate_spec "$spec"
        done

        mkdir -p "$config_dir"
        chmod 0700 "$config_dir"
        local tmp
        tmp="$(mktemp "$config_dir/.ssh-keys.tmp.XXXXXX")"
        printf '%s\n' "''${specs[@]}" > "$tmp"
        chmod 0600 "$tmp"
        mv -f "$tmp" "$config_file"
        printf 'Saved %d SSH key mapping(s) to %s\n' "''${#specs[@]}" "$config_file"
      }

      unlock_vault() {
        local status_json status current_server session
        status_json="$(bw status)"
        status="$(jq -r '.status // "unauthenticated"' <<< "$status_json")"
        current_server="$(jq -r '.serverUrl // empty' <<< "$status_json")"
        current_server="''${current_server%/}"

        if [[ "$current_server" != "$server" ]]; then
          if [[ "$status" != "unauthenticated" ]]; then
            printf 'Bitwarden CLI is logged in to %s; log out before switching to %s\n' "$current_server" "$server" >&2
            exit 1
          fi
          bw config server "$server" >/dev/null
          status="unauthenticated"
        fi

        if [[ "$status" == "unauthenticated" ]]; then
          bw login --sso >&2
        fi

        session="''${BW_SESSION:-}"
        if [[ -z "$session" ]] || ! BW_SESSION="$session" bw status | jq -e '.status == "unlocked"' >/dev/null; then
          session="$(bw unlock --raw)"
        fi
        BW_SESSION="$session" bw sync >/dev/null
        printf '%s' "$session"
      }

      if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
        usage
        exit 0
      fi
      if [[ "''${1:-}" == "configure" ]]; then
        shift
        configure "$@"
        exit 0
      fi
      if [[ "''${1:-}" == "pull" ]]; then
        shift
      fi

      specs=("$@")
      if (( ''${#specs[@]} == 0 )); then
        if [[ ! -f "$config_file" ]]; then
          printf 'No SSH key mappings found. Run bw-ssh-pull configure UUID=FILENAME ... first.\n' >&2
          exit 1
        fi
        while IFS= read -r spec; do
          [[ -z "$spec" || "$spec" == \#* ]] && continue
          specs+=("$spec")
        done < "$config_file"
      fi

      for spec in "''${specs[@]}"; do
        validate_spec "$spec"
      done

      umask 077
      mkdir -p "$ssh_dir"
      chmod 0700 "$ssh_dir"
      session="$(unlock_vault)"
      tmp=""
      cleanup() {
        [[ -z "$tmp" ]] || rm -f "$tmp"
        unset session
      }
      trap cleanup EXIT

      for spec in "''${specs[@]}"; do
        [[ "$spec" =~ ^([^=]+)=(.+)$ ]]
        uuid="''${BASH_REMATCH[1]}"
        filename="''${BASH_REMATCH[2]}"
        target="$ssh_dir/$filename"
        tmp="$(mktemp "$ssh_dir/.$filename.tmp.XXXXXX")"

        if BW_SESSION="$session" bw get item "$uuid" | jq -e '(.sshKey.privateKey? // "") != ""' >/dev/null; then
          BW_SESSION="$session" bw get item "$uuid" | jq -er '.sshKey.privateKey' > "$tmp"
        else
          BW_SESSION="$session" bw get item "$uuid" \
            | jq -er '.notes // empty | select(length > 0)' \
            | base64 --decode > "$tmp"
        fi

        chmod 0600 "$tmp"
        if ! ssh-keygen -l -f "$tmp" >/dev/null 2>&1; then
          printf 'Bitwarden item %s did not produce a valid SSH private key.\n' "$uuid" >&2
          exit 1
        fi
        mv -f "$tmp" "$target"
        tmp=""
        printf 'Installed %s (%s)\n' "$target" "$(ssh-keygen -l -f "$target" | cut -d ' ' -f 2)"
      done
    '';
  };
in
{
  home.packages = [ bw-ssh-pull ];
}
