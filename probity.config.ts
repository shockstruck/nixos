// Template file: identical in every repository that adopts repo-policy. Change
// it in shockstruck/agent-platform, not here. Everything repository-specific is
// `repository` and `probity` in .claude/hooks/policy.json.
//
// Probity carries the one rule that needs a judge: commit scope. Everything
// deterministic — blocked executables, unsafe Git and gh forms, added
// commentary, the validation gate — stays in the sibling hooks, where it costs
// no tokens and cannot be argued with.
import { defineConfig } from '@nizos/probity'
import type { Action, RuleContext, RuleResult, SessionEvent } from '@nizos/probity'
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// The repository the agent is editing, which is not necessarily the directory
// this file sits in: the dispatcher runs merged policy out of a pinned cache.
// CLAUDE_PROJECT_DIR is the checkout root and is always set by the dispatcher;
// the fallback covers running this config from the tree directly.
const ROOT = process.env.CLAUDE_PROJECT_DIR
  ? path.resolve(process.env.CLAUDE_PROJECT_DIR)
  : path.dirname(fileURLToPath(import.meta.url))

type Policy = { repository?: string; probity?: { extraInstructions?: string } }

/** The repository's slots. Policy comes from the pinned copy when there is one. */
function loadPolicy(): Policy {
  const candidates = [
    process.env.MULTICA_POLICY_DIR
      ? path.join(process.env.MULTICA_POLICY_DIR, '.claude', 'hooks', 'policy.json')
      : undefined,
    path.join(ROOT, '.claude', 'hooks', 'policy.json'),
  ].filter((candidate): candidate is string => Boolean(candidate))
  for (const candidate of candidates) {
    try {
      return JSON.parse(fs.readFileSync(candidate, 'utf8')) as Policy
    } catch {
      continue
    }
  }
  return {}
}

const POLICY = loadPolicy()
const REPOSITORY = POLICY.repository?.trim() || 'this repository'
const EXTRA_INSTRUCTIONS = POLICY.probity?.extraInstructions?.trim() ?? ''

// The built-in maxEvents / maxContentChars options belong to enforceTdd, which
// this config does not use. The custom rule windows its own history; these are
// the equivalents, sized so a commit prompt stays well inside a single turn.
const MAX_WRITE_EVENTS = 40
const MAX_PROMPT_EVENTS = 8
const MAX_CONTENT_CHARS = 800
const MAX_OUTCOME_CHARS = 300

const RESPONSE_SPEC = `## Response format

Respond with a single JSON object of exactly this shape:
{"kind":"pass"|"violation","reason":"<short explanation>"}
On "pass", leave reason an empty string (""); only a "violation" needs an explanation.
Return JSON only. No prose, no code fences.`

// A commit is what the session is about to record, so the whole session's writes
// are the unit of judgement — not the pending command text.
const COMMIT_INSTRUCTIONS = `## Role

You are reviewing the scope of a commit an agent is about to make in ${REPOSITORY}.
You judge scope only. Another gate already checks that validation ran and that the
command itself is safe.

## What you block

**Bundled scope.** The session's writes mix the change the operator asked for with
unrelated work: an incidental cleanup, a version bump, a refactor, a rename, or a
second component's configuration carried along with a fix. The rule is the smallest
reversible change per commit.

## What you must not block

- A change that is large but coherent: every write serves the one stated outcome.
- Edits that are mechanically required by the asked-for change (a new file plus the
  manifest entry that wires it, a value plus the schema that validates it, code plus
  its test).
- Repository housekeeping the operator asked for directly.
- Missing evidence. When the writes or the operator prompt are absent, do not infer
  a violation from the absence.

Each write shows the outcome the agent got back. A write whose outcome records a
denial or an error never landed: it is not part of this commit, and it is not bundled
scope. Judge the writes that succeeded.

Judge only what the inputs show. Do not speculate about files you were not given.`

type Verdict = { kind: 'pass' | 'violation'; reason: string }

function truncate(text: string, limit = MAX_CONTENT_CHARS): string {
  if (text.length <= limit) return text
  return `${text.slice(0, limit)}\n… (${text.length - limit} more characters)`
}

async function readHistory(ctx?: RuleContext): Promise<SessionEvent[] | undefined> {
  if (!ctx?.history) return undefined
  try {
    return await ctx.history()
  } catch {
    return undefined
  }
}

function formatEvent(event: SessionEvent): string {
  switch (event.kind) {
    case 'prompt':
      return `Operator: ${truncate(event.text)}`
    case 'command':
      return `Ran: ${truncate(event.command)}`
    // The outcome matters as much as the attempt: a write a hook denied left
    // nothing behind, and must not be judged as part of the change.
    case 'write':
      return `Wrote ${event.path} → ${truncate(event.output, MAX_OUTCOME_CHARS)}\n${truncate(event.content)}`
    case 'other':
      return `${event.tool}: ${truncate(String(event.output))}`
  }
}

const HOOK_LIB = path.join(ROOT, '.claude', 'hooks', 'lib')
const GIT_COMMIT_PROBE = [
  'import sys',
  `sys.path.insert(0, ${JSON.stringify(HOOK_LIB)})`,
  'from git_command import invocations',
  "found = any(i.subcommand == 'commit' for i in invocations(sys.stdin.read(), strict=False))",
  'print(1 if found else 0)',
].join('\n')

/**
 * Whether the command actually runs `git commit`, via the same tokenizer
 * `block-git-unsafe.sh` and `require-validation-before-git.sh` use: it unwraps
 * `bash -c`, `xargs` and clause chains, and strips heredoc bodies, so a command
 * that merely quotes the words "git commit" is not mistaken for one. A word
 * check first keeps the interpreter off the path of every other Bash call.
 */
function runsGitCommit(command: string): boolean {
  if (!/\bcommit\b/.test(command)) return false
  try {
    const stdout = execFileSync('python3', ['-c', GIT_COMMIT_PROBE], {
      input: command,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore'],
    })
    return stdout.trim() === '1'
  } catch {
    // The deterministic Git hooks already deny a command they cannot tokenize,
    // so an unparseable one never reaches a commit worth judging here.
    return false
  }
}

/**
 * AI-judged commit scope. One model call per `git commit`, and none at all when
 * the session recorded no writes.
 */
async function commitScope(action: Action, ctx?: RuleContext): Promise<RuleResult> {
  if (action.kind !== 'command' || !runsGitCommit(action.command)) return { kind: 'pass' }
  if (!ctx?.agent) {
    return {
      kind: 'violation',
      reason: 'commit scope: no AI validator available to judge this commit',
    }
  }

  const history = await readHistory(ctx)
  if (history === undefined) {
    return {
      kind: 'violation',
      reason:
        'commit scope: the session transcript could not be read, so the commit scope cannot be judged',
    }
  }

  const writes = history.flatMap((event) => (event.kind === 'write' ? [event] : []))
  if (writes.length === 0) return { kind: 'pass' }

  const prompts = history
    .filter((event): event is Extract<SessionEvent, { kind: 'prompt' }> => event.kind === 'prompt')
    .slice(-MAX_PROMPT_EVENTS)
  const recentWrites = writes.slice(-MAX_WRITE_EVENTS)

  const prompt = [
    EXTRA_INSTRUCTIONS ? `${COMMIT_INSTRUCTIONS}\n\n${EXTRA_INSTRUCTIONS}` : COMMIT_INSTRUCTIONS,
    `## What the operator asked for\n\n${
      prompts.length
        ? prompts.map(formatEvent).join('\n\n')
        : '(no operator prompt in the transcript)'
    }`,
    `## Writes in this session\n\n${recentWrites.map(formatEvent).join('\n')}`,
    `## Pending command\n\n${truncate(action.command, 2000)}`,
    RESPONSE_SPEC,
  ].join('\n\n')

  const verdict: Verdict = await ctx.agent.reason(prompt)
  if (verdict.kind === 'violation') {
    return { kind: 'violation', reason: `commit scope: ${verdict.reason}` }
  }
  return { kind: 'pass' }
}

export default defineConfig({
  rules: [commitScope],
})
