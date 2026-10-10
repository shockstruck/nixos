// Replays command strings through the guard's own hooks and prints a
// Markdown table; exits non-zero when any decision differs from the
// expectation. Run with `node modules/nixos/opencode-guard/replay.mjs`.
import guard from "./guard.js"

const OPERATOR = "multica-operator"

const cases = [
  // The F2 forms the policy patterns cannot see.
  [OPERATOR, "{ cat /etc/hostname; } > ~/.config/opencode/opencode.json", "deny"],
  [OPERATOR, "(cat /etc/hostname) > f", "deny"],
  [OPERATOR, "for u in a b; do systemctl status $u; done > f", "deny"],
  [OPERATOR, "> ~/.config/opencode/opencode.json", "deny"],
  [OPERATOR, "cat a >> f", "deny"],
  [OPERATOR, "journalctl -b 2>&1", "deny"],
  [OPERATOR, "cat < /etc/shadow", "deny"],
  [OPERATOR, "cat <(ls)", "deny"],
  [OPERATOR, "grep x /etc/hosts | tail -n 1 > f", "deny"],
  [OPERATOR, "ls $(cat f)", "deny"],
  [OPERATOR, "{ ls $(cat f); }", "deny"],
  [OPERATOR, 'ls "$(cat f)"', "deny"],
  [OPERATOR, "ls `cat f`", "deny"],
  [OPERATOR, 'ls "`cat f`"', "deny"],
  [OPERATOR, "while true; do ls `id`; done", "deny"],
  [OPERATOR, "journalctl -u nix-daemon | grep https://example.com", "deny"],
  [OPERATOR, "grep 'https://example.com' /etc/hosts", "deny"],
  [OPERATOR, "ip route get example.com", "deny"],
  [OPERATOR, "systemctl status foo --host=evil.example.org", "deny"],
  [OPERATOR, "lsof -i @evil.example.org", "deny"],
  [OPERATOR, "nmcli connection show kevin@example.org", "deny"],
  [OPERATOR, "H=example.org ls", "deny"],
  [OPERATOR, "ss -tn dst example.org:443", "deny"],
  [OPERATOR, "ip route get $'\\x65xample.org'", "deny"],
  [OPERATOR, "ip route get example.{org,net}", "deny"],
  [OPERATOR, "ip route get ${H:-example.org}", "deny"],
  [OPERATOR, "cat 'unterminated", "deny"],
  // Quoted or escaped metacharacters are literal arguments.
  [OPERATOR, "grep '>' /etc/fstab", "allow"],
  [OPERATOR, "grep '$(x)' /etc/profile", "allow"],
  [OPERATOR, 'grep "a>b" /etc/fstab', "allow"],
  [OPERATOR, "grep \\> /etc/fstab", "allow"],
  // Ordinary operator diagnostics.
  [OPERATOR, "systemctl status multica-daemon.service", "allow"],
  [OPERATOR, "systemctl status getty@tty1.service user@1000.service", "allow"],
  [OPERATOR, "journalctl -u nix-daemon.service -b -n 200 --no-pager", "allow"],
  [OPERATOR, "journalctl -b | grep -i amdgpu | tail -n 50", "allow"],
  [OPERATOR, "flatpak info com.valvesoftware.Steam", "allow"],
  [OPERATOR, "grep -r netbird.io /etc/netbird", "allow"],
  [OPERATOR, "cat /etc/resolv.conf; ip addr show", "allow"],
  [OPERATOR, "{ uname -a; uptime; }", "allow"],
  [OPERATOR, "modinfo amdgpu && lsmod", "allow"],
  [OPERATOR, "multica issue comment add 01a0 --content-file ./reply.md", "allow"],
  // Any other agent: the guard is inert, whatever the command.
  ["build", "{ cat a; } > f; curl https://example.com $(id) `id`", "allow"],
  ["plan", "ip route get example.com", "allow"],
]

const server = await guard.server({})
const decide = async (agent, command, session) => {
  await server["chat.message"]({ sessionID: session }, { message: { agent }, parts: [] })
  try {
    await server["tool.execute.before"]({ tool: "bash", sessionID: session, callID: "c" }, { args: { command } })
    return ["allow", ""]
  } catch (error) {
    return ["deny", error.message.replace(/^multica-operator guard: /, "")]
  }
}

const cell = (text) => "`" + text.replaceAll("|", "\\|").replaceAll("`", "ˋ") + "`"
let failures = 0
console.log("| # | agent | command | expected | decision | reason |")
console.log("|---|---|---|---|---|---|")
for (const [n, [agent, command, expected]] of cases.entries()) {
  const [decision, reason] = await decide(agent, command, `s${n}`)
  if (decision !== expected) failures++
  const mark = decision === expected ? decision : `**${decision} (MISMATCH)**`
  console.log(`| ${n + 1} | ${agent} | ${cell(command)} | ${expected} | ${mark} | ${reason.replaceAll("|", "\\|")} |`)
}

// A session the guard never saw a message for is denied, not guessed.
let unknown = "allow"
try {
  await server["tool.execute.before"]({ tool: "bash", sessionID: "never-seen", callID: "c" }, { args: { command: "ls" } })
} catch {
  unknown = "deny"
}
if (unknown !== "deny") failures++
console.log(`| ${cases.length + 1} | (unseen session) | ${cell("ls")} | deny | ${unknown} | agent unknown |`)

// Non-bash tools pass through untouched.
let other = "allow"
try {
  await server["tool.execute.before"]({ tool: "read", sessionID: "s0", callID: "c" }, { args: { filePath: "/etc/x > y" } })
} catch {
  other = "deny"
}
if (other !== "allow") failures++
console.log(`| ${cases.length + 2} | ${OPERATOR} (read tool) | ${cell("/etc/x > y")} | allow | ${other} | not bash |`)

console.log(`\n${cases.length + 2} cases, ${failures} mismatches`)
process.exit(failures ? 1 : 0)
