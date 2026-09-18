"""Audit comments on handwritten DSLX declarations; XLS remains the type checker.

This reader locates declaration boundaries, not expressions. It skips balanced
bodies and literals, and rejects unfamiliar declaration forms instead of silently
losing coverage. Generated DSLX is excluded by the caller's repository scope.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re


@dataclass(frozen=True)
class Token:
    """One source token with its location and any immediately preceding comment."""

    text: str
    line: int
    documented: bool = False


class SourceError(ValueError):
    """An unsupported or incomplete declaration that must fail the audit."""

    def __init__(self, line: int, reason: str) -> None:
        """Retain a useful source location for the diagnostic."""
        super().__init__(reason)
        self.line = line


LEXEME = re.compile(
    r'//[^\n]*|/\*[\s\S]*?\*/|\s+|"(?:\\[\s\S]|[^"\\])*"'
    r"|'(?:\\.|[^'\\])'|[A-Za-z_][A-Za-z_0-9]*|[0-9][A-Za-z_0-9]*|[^\w\s]"
)
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z_0-9]*\Z")
PAIRS = {"(": ")", "[": "]", "{": "}"}


def tokens(source: str) -> list[Token]:
    """Separate code from comments/literals without interpreting expressions."""
    result = []
    line, offset, comment_line = 1, 0, 0
    documented = False
    for match in LEXEME.finditer(source):
        text = match.group()
        if match.start() != offset or text in {'"', "'"}:
            raise SourceError(line, "unrecognized token or unterminated literal")
        end_line = line + text.count("\n")
        if text.startswith(("//", "/*")):
            # A trailing comment belongs to the preceding declaration, never
            # to the next one. Punctuation-only separators are not prose.
            if not result or result[-1].line < line:
                documented = documented or any(c.isalnum() for c in text)
                comment_line = end_line
        elif not text.isspace():
            result.append(Token(text, line, documented and line <= comment_line + 1))
            documented = False
        elif end_line > comment_line + 1:
            documented = False
        line, offset = end_line, match.end()
    if offset != len(source):
        raise SourceError(line, "unrecognized token")
    return result


class Reader:
    """Collect declaration contracts while treating expression bodies as opaque."""

    def __init__(self, source: str, path: str) -> None:
        """Prepare one inert source file for boundary inspection."""
        self.code = tokens(source)
        self.path = path
        self.index = 0
        self.gaps: list[dict[str, object]] = []

    def peek(self) -> str:
        """Return the next token, or an empty end-of-file marker."""
        return self.code[self.index].text if self.index < len(self.code) else ""

    def fail(self, reason: str) -> None:
        """Stop at the current token rather than accepting partial coverage."""
        line = self.code[min(self.index, len(self.code) - 1)].line if self.code else 1
        raise SourceError(line, reason)

    def take(self, expected: str | None = None) -> str:
        """Consume one required token, optionally checking its spelling."""
        text = self.peek()
        if not text or (expected is not None and text != expected):
            self.fail(f"expected {expected or 'token'}, found {text or 'end of file'}")
        self.index += 1
        return text

    def name(self) -> str:
        """Consume a declaration name, rejecting malformed headers."""
        if not IDENTIFIER.fullmatch(self.peek()):
            self.fail("expected declaration name")
        return self.take()

    def group(self) -> None:
        """Skip balanced brackets, including nested default-value expressions."""
        closing = PAIRS[self.take()]
        while self.peek() != closing:
            if self.peek() in PAIRS:
                self.group()
            elif not self.peek() or self.peek() in PAIRS.values():
                self.fail(f"unclosed group; expected {closing}")
            else:
                self.take()
        self.take(closing)

    def parameters(self) -> None:
        """Skip a parametric header, including defaults and nested type arguments."""
        if self.peek() != "<":
            return
        self.take("<")
        while self.peek() != ">":
            if self.peek() == "<":
                self.parameters()
            elif self.peek() in PAIRS:
                self.group()
            elif not self.peek() or self.peek() in (";", "}"):
                self.fail("unclosed parametric header")
            else:
                self.take()
        self.take(">")

    def through_semicolon(self) -> None:
        """Skip a binding, alias or import without mistaking its value for code."""
        while self.peek() != ";":
            if self.peek() in PAIRS:
                self.group()
            elif self.peek() in ("", "}"):
                self.fail("expected declaration terminator")
            else:
                self.take()
        self.take(";")

    def contract(self, start: int, identity: str, public: bool, documented: bool) -> None:
        """Require prose and fingerprint code independently of comments/formatting."""
        if documented:
            return
        body = [t.text for t in self.code[start:self.index]]
        fingerprint = hashlib.sha256(json.dumps(body).encode()).hexdigest()
        self.gaps.append({"path": self.path, "line": self.code[start].line,
                          "id": identity, "rule": "public_doc" if public else "private_comment",
                          "fingerprint": fingerprint})

    def declaration(self, owner: str = "") -> None:
        """Inspect one top-level declaration or one proc lifecycle member."""
        start = self.index
        documented = self.code[start].documented
        # Attributes belong to the declaration; comments on either side count.
        while self.peek() == "#":
            self.take("#")
            if self.peek() == "!":
                self.take("!")
            if self.peek() != "[":
                self.fail("expected attribute")
            self.group()
            if self.peek():
                documented |= self.code[self.index].documented
        public = self.peek() == "pub"
        if public:
            self.take("pub")
        kind = self.take()
        if kind in ("import", "use", "const", "const_assert"):
            self.through_semicolon()
            return
        if owner and kind in ("config", "init", "next"):
            name, kind = f"{owner}.{kind}", "fn"
        elif kind in ("fn", "proc", "struct", "enum", "type"):
            name = self.name()
            if owner:
                name = f"{owner}.{name}"
            self.parameters()
        elif owner and IDENTIFIER.fullmatch(kind) and self.peek() == ":":
            self.through_semicolon()  # Proc channel/state member, not a declaration contract.
            return
        else:
            self.fail(f"unsupported declaration: {kind}")
        if kind == "type":
            self.through_semicolon()
        else:
            # Headers contain argument lists, arrays and parametric result types.
            while self.peek() != "{":
                if self.peek() in PAIRS:
                    self.group()
                elif self.peek() == "<":
                    self.parameters()
                elif self.peek() in ("", ";", "}"):
                    self.fail("expected declaration body")
                else:
                    self.take()
            if kind == "proc":
                self.take("{")
                while self.peek() != "}":
                    if not self.peek():
                        self.fail("unclosed proc")
                    self.declaration(name)
                self.take("}")
            else:
                self.group()
        identity = f"{'function' if kind == 'fn' else kind}:{name}"
        self.contract(start, identity, public, documented)


def findings(paths: list[str], cwd: str) -> list[dict[str, object]]:
    """Audit all selected files; unsupported syntax is an unconditional failure."""
    gaps = []
    for path in paths:
        try:
            reader = Reader((Path(cwd) / path).read_text(), path)
            while reader.peek():
                reader.declaration()
            gaps.extend(reader.gaps)
        except SourceError as error:
            gaps.append({"path": path, "line": error.line, "id": "source", "rule": "parse",
                         "fingerprint": "", "reason": str(error)})
    return gaps
