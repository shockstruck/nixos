# shellcheck shell=bash

# Materialises the broker's encoded JIT payload as the pinned runner's own
# state files. Arguments: the payload file, the runner root, the runner user
# and the one repository URL a `.runner` must pin. The outer payload is base64
# of a JSON object that maps a config file name to that file's base64 content;
# actions/runner's `Runner.cs` writes each key under `RUNNER_ROOT`. Only the
# pinned runner's known config names are accepted. No payload string is used as
# a path, put in argv or logged, and nothing is written until every accepted
# state file has validated.

payload="$1"
runnerRoot="$2"
runnerUser="$3"
expectedUrl="$4"
stateDir="$(mktemp -d --tmpdir project-alpha-jit.XXXXXXXXXX)"
trap 'rm -rf "$stateDir"' EXIT

reject() {
  echo "$*" >&2
  exit 1
}

# jq reads a stream of JSON documents and `-e` only reports the last one, so a
# decoded value that carries extra documents must not pass. Slurp the decode,
# require exactly one object and print just that object; every later check runs
# on this extracted file.
object_document() {
  jq -ces 'if length == 1 and (.[0] | type) == "object" then .[0] else empty end' "$1"
}

if ! [ -s "$payload" ]; then
  reject "JIT payload is missing or empty"
fi
if ! [ -d "$runnerRoot" ]; then
  reject "runner state directory is missing: $runnerRoot"
fi

if ! base64 --decode "$payload" > "$stateDir/payload.decoded.json" 2>/dev/null; then
  reject "JIT payload is not valid base64"
fi
if ! object_document "$stateDir/payload.decoded.json" > "$stateDir/payload.json" 2>/dev/null; then
  reject "JIT payload is not a JSON object"
fi

unknown="$(jq -r --argjson allowed '[".runner",".credentials",".credentials_rsaparams"]' 'keys_unsorted - $allowed | .[]' "$stateDir/payload.json")"
if [ -n "$unknown" ]; then
  reject "JIT payload names unsupported runner state: $unknown"
fi
if ! jq -e 'has(".runner") and has(".credentials")' "$stateDir/payload.json" >/dev/null; then
  reject "JIT payload is missing .runner or .credentials"
fi

if ! jq -r '.[".runner"]' "$stateDir/payload.json" | base64 --decode > "$stateDir/runner.decoded.json" 2>/dev/null; then
  reject "JIT .runner state is not valid base64"
fi
if ! object_document "$stateDir/runner.decoded.json" > "$stateDir/runner.json" 2>/dev/null; then
  reject "JIT .runner state is not an object with unique alphanumeric keys"
fi

# `.runner` is read by Newtonsoft, which matches its property names ignoring
# case. Accept only a plain object whose keys are alphanumeric and unique when
# case is folded, then look every setting up the same way. `\A` and `\z` keep
# a trailing newline out of a key, which `$` would admit.
if ! jq -e '
  type == "object"
  and (keys | all(test("\\A[A-Za-z0-9]+\\z")))
  and (([keys[] | ascii_downcase] | length) == ([keys[] | ascii_downcase] | unique | length))
' "$stateDir/runner.json" >/dev/null 2>&1; then
  reject "JIT .runner state is not an object with unique alphanumeric keys"
fi

# The pinned runner's `RunnerSettings.Ephemeral` is a bool; Newtonsoft also
# coerces the strings "true"/"false" without regard to case.
if ! jq -e '
  [to_entries[] | select(.key | ascii_downcase == "ephemeral")] as $matches
  | ($matches | length) == 1
    and (
      ($matches[0].value == true)
      or ((($matches[0].value | type) == "string") and (($matches[0].value | ascii_downcase) == "true"))
    )
' "$stateDir/runner.json" >/dev/null; then
  reject "JIT .runner state is not ephemeral"
fi

if ! jq -e '
  [to_entries[] | select(.key | ascii_downcase == "workfolder")] as $matches
  | ($matches | length) == 1
    and (($matches[0].value | type) == "string")
    and (($matches[0].value | length) > 0)
' "$stateDir/runner.json" >/dev/null; then
  reject "JIT .runner state has no non-empty workFolder"
fi

if ! jq -e '
  [to_entries[] | select(.key | ascii_downcase == "githuburl")] | length == 1
' "$stateDir/runner.json" >/dev/null; then
  reject "JIT .runner state is missing gitHubUrl"
fi
if ! jq -e --arg url "$expectedUrl" '
  [to_entries[] | select(.key | ascii_downcase == "githuburl")][0].value == $url
' "$stateDir/runner.json" >/dev/null; then
  reject "JIT .runner state gitHubUrl does not match the expected repository"
fi

if ! jq -r '.[".credentials"]' "$stateDir/payload.json" | base64 --decode > "$stateDir/credentials.decoded" 2>/dev/null; then
  reject "JIT .credentials state is not valid base64"
fi
if ! [ -s "$stateDir/credentials.decoded" ]; then
  reject "JIT .credentials state is empty"
fi
if ! object_document "$stateDir/credentials.decoded" > "$stateDir/credentials.json" 2>/dev/null; then
  reject "JIT .credentials state is not a JSON object"
fi

haveRsaparams=0
if jq -e 'has(".credentials_rsaparams")' "$stateDir/payload.json" >/dev/null; then
  if ! jq -r '.[".credentials_rsaparams"]' "$stateDir/payload.json" | base64 --decode > "$stateDir/rsaparams" 2>/dev/null; then
    reject "JIT .credentials_rsaparams state is not valid base64"
  fi
  haveRsaparams=1
fi

# Write what was checked: `.runner` is the compact object extracted above, and
# `.credentials` is written exactly as decoded.
rm -f "$runnerRoot/.runner" "$runnerRoot/.credentials" "$runnerRoot/.credentials_rsaparams"
install -m 0600 -o "$runnerUser" -g "$runnerUser" "$stateDir/runner.json" "$runnerRoot/.runner"
install -m 0600 -o "$runnerUser" -g "$runnerUser" "$stateDir/credentials.decoded" "$runnerRoot/.credentials"
if [ "$haveRsaparams" = "1" ]; then
  install -m 0600 -o "$runnerUser" -g "$runnerUser" "$stateDir/rsaparams" "$runnerRoot/.credentials_rsaparams"
fi
