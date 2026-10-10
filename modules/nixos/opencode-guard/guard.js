// opencode server plugin loaded from the managed config tier
// (../opencode-policy.nix). It checks the whole `bash` command string of the
// `multica-operator` agent before the call runs, because the `bash`
// permission patterns in the policy never see all of it: opencode asks each
// `command` node of the parsed tree on its own, taking the redirection only
// when the node's direct parent is a `redirected_statement`, so
// `{ cat a; } > f`, `(cat a) > f` and `for ...; done > f` are asked as
// `cat a`, and a string with no command node (`> f`) asks nothing at all
// (anomalyco/opencode v1.18.31 packages/opencode/src/tool/shell.ts:119-125,
// 282).
//
// A `tool.execute.before` hook that throws stops the call before the tool
// runs (session/tools.ts:106-111, plugin/index.ts:291-295). The hook input
// carries no agent name, so the agent of each session is taken from
// `chat.message`, which fires for every user message with the resolved agent
// before the loop runs (session/prompt.ts:635-662, 999-1009, 1170). A session
// whose agent was never seen is denied rather than guessed.
//
// Plain JavaScript with no imports: opencode imports a path plugin as is,
// with no install or build step (plugin/loader.ts:94-141,
// plugin/shared.ts:171-187, 207-208).

const AGENT = "multica-operator"

// Commands whose arguments name local things only (files, units, Flatpak
// refs, modules) and never reach the resolver; their arguments skip the
// hostname check. Everything else, including any command not listed, is
// checked.
const LOCAL_COMMANDS = new Set([
  "cat",
  "date",
  "df",
  "dmesg",
  "du",
  "eglinfo",
  "file",
  "findmnt",
  "flatpak",
  "free",
  "getfacl",
  "grep",
  "head",
  "id",
  "ls",
  "lsblk",
  "lscpu",
  "lsmod",
  "lsusb",
  "modinfo",
  "nvidia-smi",
  "pgrep",
  "ps",
  "readlink",
  "rocm-smi",
  "sensors",
  "stat",
  "tail",
  "top",
  "uname",
  "uptime",
  "vulkaninfo",
  "wc",
  "which",
])

// Final labels that mark a file name or a systemd unit rather than a host.
const LOCAL_SUFFIXES = new Set([
  "automount",
  "bak",
  "bin",
  "cache",
  "cfg",
  "conf",
  "csv",
  "d",
  "db",
  "desktop",
  "device",
  "efi",
  "gz",
  "img",
  "ini",
  "journal",
  "js",
  "json",
  "jsonc",
  "ko",
  "link",
  "list",
  "lock",
  "log",
  "md",
  "mount",
  "netdev",
  "network",
  "nix",
  "old",
  "path",
  "pid",
  "py",
  "rules",
  "scope",
  "service",
  "sh",
  "slice",
  "so",
  "sock",
  "socket",
  "swap",
  "target",
  "timer",
  "toml",
  "ts",
  "txt",
  "xml",
  "xz",
  "yaml",
  "yml",
  "zst",
])

const HOST = /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z](?:[a-z0-9-]{0,61}[a-z0-9])?)\.?$/i
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/
const SEPARATORS = new Set([";", "&", "|", "(", ")", "\n"])
const BLANKS = new Set([" ", "\t", "\r"])

function hostLike(text) {
  const bare = text.replace(/^\[|\]$/g, "").replace(/:\d+$/, "")
  const match = HOST.exec(bare)
  return match !== null && !LOCAL_SUFFIXES.has(match[1].toLowerCase())
}

// A word reaches the resolver as a host when it is a dotted DNS name, the
// value of `--flag=`, or the part after an `@`; a path is never one.
export function hostnameShaped(word) {
  if (word.includes("/") || word.includes("\\")) return false
  let value = word
  if (value.startsWith("-")) {
    const eq = value.indexOf("=")
    if (eq < 0) return false
    value = value.slice(eq + 1)
  }
  if (hostLike(value)) return true
  const at = value.lastIndexOf("@")
  return at >= 0 && hostLike(value.slice(at + 1))
}

// Splits a command string the way bash quotes it, collecting the words of
// each simple command and every construct that redirects, substitutes or
// expands into something the policy patterns cannot see.
export function lex(command) {
  const findings = new Set()
  const commands = [[]]
  let word = null
  const s = command

  const flush = () => {
    if (word !== null) commands[commands.length - 1].push(word)
    word = null
  }
  const boundary = () => {
    flush()
    if (commands[commands.length - 1].length) commands.push([])
  }
  const append = (c) => {
    word = (word ?? "") + c
  }

  let i = 0
  while (i < s.length) {
    const c = s[i]
    if (c === "\\") {
      if (i + 1 < s.length && s[i + 1] !== "\n") append(s[i + 1])
      i += 2
      continue
    }
    if (c === "'") {
      const end = s.indexOf("'", i + 1)
      if (end < 0) {
        findings.add("unterminated quote")
        break
      }
      append(s.slice(i + 1, end))
      i = end + 1
      continue
    }
    if (c === "$" && s[i + 1] === "'") {
      // Its escapes can spell any character, so it is denied outright.
      findings.add("ANSI-C quoting ($'...')")
      let j = i + 2
      while (j < s.length && s[j] !== "'") j += s[j] === "\\" ? 2 : 1
      if (j >= s.length) {
        findings.add("unterminated quote")
        break
      }
      append(s.slice(i + 2, j))
      i = j + 1
      continue
    }
    if (c === "$" && s[i + 1] === "(") {
      findings.add("command substitution ($(...))")
      append(c)
      i += 1
      continue
    }
    if (c === "`") {
      findings.add("backtick command substitution")
      i += 1
      continue
    }
    if (c === '"' || (c === "$" && s[i + 1] === '"')) {
      i += c === "$" ? 2 : 1
      let closed = false
      word = word ?? ""
      while (i < s.length) {
        const d = s[i]
        if (d === '"') {
          closed = true
          i += 1
          break
        }
        if (d === "\\" && i + 1 < s.length) {
          const e = s[i + 1]
          if ("$`\"\\".includes(e)) word += e
          else if (e !== "\n") word += d + e
          i += 2
          continue
        }
        if (d === "`") findings.add("backtick command substitution")
        if (d === "$" && s[i + 1] === "(") findings.add("command substitution ($(...))")
        word += d
        i += 1
      }
      if (!closed) {
        findings.add("unterminated quote")
        break
      }
      continue
    }
    if (c === ">" || c === "<") {
      findings.add(s[i + 1] === "(" ? "process substitution" : "redirection")
      flush()
      i += 1
      continue
    }
    if ((c === "{" || c === "}") && word !== null) {
      findings.add("brace or parameter expansion")
    }
    if (c === "{" || c === "}") {
      const next = s[i + 1]
      if (word === null && (next === undefined || BLANKS.has(next) || SEPARATORS.has(next))) {
        boundary()
        i += 1
        continue
      }
      if (word === null) findings.add("brace or parameter expansion")
      append(c)
      i += 1
      continue
    }
    if (SEPARATORS.has(c)) {
      boundary()
      i += 1
      continue
    }
    if (BLANKS.has(c)) {
      flush()
      i += 1
      continue
    }
    append(c)
    i += 1
  }
  flush()
  return { findings, commands: commands.filter((words) => words.length) }
}

// The reasons a command string is denied; empty when it may run.
export function inspect(command) {
  if (typeof command !== "string") return ["command is not a string"]
  const { findings, commands } = lex(command)
  const reasons = [...findings]
  if (command.includes("://")) reasons.push("URL")
  for (const words of commands) {
    let k = 0
    for (; k < words.length && ASSIGNMENT.test(words[k]); k++) {
      const value = words[k].slice(words[k].indexOf("=") + 1)
      if (hostnameShaped(value)) reasons.push(`hostname-shaped assignment: ${words[k]}`)
    }
    if (k >= words.length || LOCAL_COMMANDS.has(words[k])) continue
    for (const arg of words.slice(k + 1)) {
      if (hostnameShaped(arg)) reasons.push(`hostname-shaped argument to ${words[k]}: ${arg}`)
    }
  }
  return reasons
}

export default {
  id: "multica-operator-guard",
  server: async () => {
    const agents = new Map()
    return {
      "chat.message": async (input, output) => {
        const agent = output?.message?.agent ?? input?.agent
        if (input?.sessionID && agent) agents.set(input.sessionID, agent)
      },
      "tool.execute.before": async (input, output) => {
        if (input?.tool !== "bash") return
        const agent = agents.get(input.sessionID)
        if (agent === undefined) {
          throw new Error("multica-operator guard: the agent of this session is unknown, so bash is denied")
        }
        if (agent !== AGENT) return
        const reasons = inspect(output?.args?.command)
        if (reasons.length) {
          throw new Error(`multica-operator guard: denied (${reasons.join("; ")})`)
        }
      },
    }
  },
}
