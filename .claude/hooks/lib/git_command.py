"""Git invocation parsing shared by the Git PreToolUse hooks.

`block-git-unsafe.sh` judges the flags of the command about to run;
`require-validation-before-git.sh` needs the same parse over the session's
history to know which subcommands already ran. Both walk the shell wrappers via
`shell_command.walk`.
"""

from __future__ import annotations

from typing import NamedTuple

from shell_command import Denial, walk

GLOBAL_VALUE_OPTIONS = {
    "-C",
    "-c",
    "--config-env",
    "--exec-path",
    "--git-dir",
    "--namespace",
    "--super-prefix",
    "--work-tree",
}


class Invocation(NamedTuple):
    subcommand: str
    arguments: list[str]


def subcommand(arguments: list[str]) -> Invocation:
    """The git subcommand and its arguments, past any global options."""
    index = 0
    while index < len(arguments):
        token = arguments[index]
        if not token.startswith("-"):
            return Invocation(token, arguments[index + 1 :])
        option = token.split("=", 1)[0]
        index += 1
        if option in GLOBAL_VALUE_OPTIONS and "=" not in token and index < len(arguments):
            index += 1
    return Invocation("", [])


def invocations(command: str, strict: bool = True) -> list[Invocation]:
    """Every git subcommand a shell command runs, wrappers included.

    With `strict`, a command that cannot be tokenized safely raises `Denial`;
    without it -- replaying session history, where an uninspectable command
    already ran -- it contributes nothing.
    """
    found: list[Invocation] = []

    def visit(executable: str, arguments: list[str]) -> None:
        if executable == "git":
            found.append(subcommand(arguments))

    try:
        walk(command, visit)
    except Denial:
        if strict:
            raise
        return found
    return found


def parse(
    arguments: list[str],
    value_letters: str = "",
    value_long: set[str] | None = None,
) -> tuple[set[str], set[str], list[str]]:
    """Split subcommand arguments into short flags, long options and operands.

    A short option that takes a value consumes the rest of its cluster
    (`-mfix`) or the next token (`-m fix`), so a value is never mistaken for a
    flag.
    """
    value_long = value_long or set()
    flags: set[str] = set()
    longs: set[str] = set()
    operands: list[str] = []
    index = 0
    while index < len(arguments):
        token = arguments[index]
        if token == "--":
            operands.extend(arguments[index + 1 :])
            break
        if token.startswith("--"):
            name = token.split("=", 1)[0]
            longs.add(name)
            index += 1
            if name in value_long and "=" not in token and index < len(arguments):
                index += 1
            continue
        if token.startswith("-") and len(token) > 1:
            attached = False
            takes_value = False
            for position, letter in enumerate(token[1:]):
                flags.add(letter)
                if letter in value_letters:
                    takes_value = True
                    attached = position < len(token) - 2
                    break
            index += 1
            if takes_value and not attached and index < len(arguments):
                index += 1
            continue
        operands.append(token)
        index += 1
    return flags, longs, operands
