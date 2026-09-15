"""Bounded, typed source generation and structural reductions for compiler probes.

Trees describe source syntax, never its evaluation. BEAM executes the rendered
Erlang. Each integer operation has an explicit normalization boundary; comparisons
therefore see the same precision on both targets.
"""
from __future__ import annotations

import hashlib
import json
import random
from collections import Counter

TYPES = {"u8": (8, False), "s8": (8, True), "u32": (32, False), "s32": (32, True)}
WORD_BINARY = ("+", "-", "*", "band", "bor", "bxor", "div", "rem")
COMPARISONS = ("=:=", "=/=", "<", "=<", ">", ">=")


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def random_for(seed, case_id):
    # Independent cases: changing batch size or a preceding case cannot change it.
    digest = hashlib.sha256(f"erl-hls-differential-v1:{seed}:{case_id}".encode()).digest()
    return random.Random(int.from_bytes(digest, "big"))


class Generator:
    def __init__(self, rng, word_type, total=False):
        self.rng = rng
        self.word_type = word_type
        self.total = total

    def leaf(self, bound):
        choices = [["var", "X"], ["var", "Y"], ["const", self.rng.choice([-1, 0, 1, 2, 3, 7])]]
        if bound:
            choices.append(["bound", self.rng.randrange(bound)])
        return self.rng.choice(choices)

    def word(self, depth, bound=0, calls=True):
        if depth <= 0:
            return self.leaf(bound)
        op = self.rng.choice(["leaf", "binary", "binary", "bnot", "select",
                              "if", "let", "join", "pair", "nth", "record"] +
                             ([] if self.total else ["partial", "match"]) +
                             (["call"] if calls else []))
        word = lambda: self.word(depth - 1, bound, calls)
        boolean = lambda: self.boolean(depth - 1, bound, calls)
        if op == "leaf":
            return self.leaf(bound)
        if op == "binary":
            operators = WORD_BINARY[:-2] if self.total else WORD_BINARY
            return ["binary", self.rng.choice(operators), word(), word()]
        if op == "bnot":
            return [op, word()]
        if op in ("select", "join"):
            return [op, boolean(), word(), word()] + (
                [self.word(depth - 1, bound + 1, calls)] if op == "join" else [])
        if op == "partial":
            return [op, word(), self.rng.randrange(4), word()]
        if op == "if":
            # rem cannot overflow, even for signed-min / -1. Guard arithmetic
            # has no normalization calls (remote calls are not legal guards).
            return [op, self.rng.choice(["compare", "rem", "alternative"]), word(),
                    word(), self.total or self.rng.choice([True, False])]
        if op == "let":
            return [op, word(), self.word(depth - 1, bound + 1, calls)]
        if op == "pair":
            return [op, word(), word(), self.word(depth - 1, bound + 2, calls)]
        if op == "match":
            return [op, self.rng.randrange(4), word(), word()]
        if op == "nth":
            if self.total:
                array = self.array(depth - 1, bound, calls)
                return [op, ["const", self.rng.randint(1, array_size(array))], array]
            return [op, word(), self.array(depth - 1, bound, calls)]
        if op == "record":
            return [op, word(), word(), self.rng.choice(["a", "b"])]
        if op == "call":
            return [op, word(), word(), self.array(depth - 1, bound, calls, slicing=False)]
        raise AssertionError(op)

    def boolean(self, depth, bound, calls):
        if depth <= 0 or self.rng.randrange(3) == 0:
            return ["compare", self.rng.choice(COMPARISONS), self.leaf(bound), self.leaf(bound)]
        if self.rng.randrange(3) == 0:
            return ["not", self.boolean(depth - 1, bound, calls)]
        if self.rng.randrange(2) == 0:
            return ["compare", self.rng.choice(COMPARISONS),
                    self.word(depth - 1, bound, calls), self.word(depth - 1, bound, calls)]
        return [self.rng.choice(["andalso", "orelse"]),
                self.boolean(depth - 1, bound, calls), self.boolean(depth - 1, bound, calls)]

    def array(self, depth, bound, calls, slicing=True):
        if depth <= 0:
            return ["values"]
        op = self.rng.choice(["values", "set", "sublist"] + (["slice"] if slicing else []))
        word = lambda: self.word(depth - 1, bound, calls)
        child = lambda: self.array(depth - 1, bound, calls, slicing=slicing)
        if op == "values":
            return [op]
        if self.total:
            array = child()
            size = array_size(array)
            if op == "set":
                return [op, ["const", self.rng.randint(1, size)], array, word()]
            if op == "sublist":
                return [op, array, ["const", 1], ["const", self.rng.randint(0, size)]]
            return [op, self.rng.randint(1, min(2, size)), array, ["const", 1]]
        if op == "set":
            return [op, word(), child(), word()]
        if op == "sublist":
            return [op, child(), word(), word()]
        return [op, self.rng.choice([1, 2]), child(), word()]


def generate(seed, case_id, depth=3, input_count=20):
    rng = random_for(seed, case_id)
    name = list(TYPES)[case_id % len(TYPES)]
    width, _ = TYPES[name]
    # Alternate groups of all four types: total programs exercise successful
    # deep paths as well as fallible programs exercising early failure selection.
    total = case_id // len(TYPES) % 2 == 0
    g = Generator(rng, name, total=total)
    mask = (1 << width) - 1
    edges = [0, 1, 2, 3, 4, 7, mask >> 1, 1 << (width - 1), mask - 1, mask]
    sign = 1 << (width - 1)
    pairs = [(0, 0), (0, 1), (1, 0), (1, 1), (sign, mask), (mask, sign),
             (sign - 1, mask), (sign, sign), (mask, mask), (sign, 1),
             (sign - 1, 1), (1, mask), (1, 2), (2, 1), (3, 3), (mask - 1, 2)]
    inputs = []
    for i in range(input_count):
        x, y = pairs[i] if i < len(pairs) else (rng.getrandbits(width), rng.getrandbits(width))
        values = ([edges[(i + j) % len(edges)] for j in range(3)]
                  if i < len(pairs) else [rng.getrandbits(width) for _ in range(3)])
        inputs.append([x, y, *values])
    return {"schema": 1, "seed": seed, "case_id": case_id, "type": name, "total": total,
            "expression": g.word(depth), "helper": g.word(max(1, depth - 1), calls=False),
            "inputs": inputs}


def array_size(node):
    if node[0] == "values":
        return 3
    if node[0] == "slice":
        return node[1]
    return array_size(node[2] if node[0] == "set" else node[1])


class Emitter:
    def __init__(self, word_type, helper):
        self.word_type, self.helper, self.serial = word_type, helper, 0

    def fresh(self):
        self.serial += 1
        return f"B{self.serial}"

    def wrap(self, expression, word_type=None):
        return f"hls_nums:wrap(hls_nums:{word_type or self.word_type}(), {expression})"

    def emit(self, n, bindings=()):
        op = n[0]
        emit = lambda v: self.emit(v, bindings)
        if op == "var":
            return n[1]
        if op == "bound":
            return bindings[n[1]]
        if op == "const":
            return self.wrap(str(n[1]))
        if op == "binary":
            return self.wrap(f"({emit(n[2])} {n[1]} {emit(n[3])})")
        if op == "bnot":
            return self.wrap(f"(bnot {emit(n[1])})")
        if op == "compare":
            return f"({emit(n[2])} {n[1]} {emit(n[3])})"
        if op in ("andalso", "orelse"):
            return f"({emit(n[1])} {op} {emit(n[2])})"
        if op == "not":
            return f"(not {emit(n[1])})"
        if op == "select":
            return f"(case {emit(n[1])} of true -> {emit(n[2])}; false -> {emit(n[3])} end)"
        if op == "partial":
            return f"(case {emit(n[1])} of {n[2]} -> {emit(n[3])} end)"
        if op == "if":
            guard = {"compare": "X =:= Y", "rem": "X rem Y =:= 0",
                     "alternative": "X rem Y > 0; X =:= 0"}[n[1]]
            fallback = f"; true -> {emit(n[3])}" if n[4] else ""
            return f"(if {guard} -> {emit(n[2])}{fallback} end)"
        if op == "let":
            name = self.fresh()
            return f"(begin {name} = {emit(n[1])}, {self.emit(n[2], (name,) + bindings)} end)"
        if op == "join":
            name = self.fresh()
            return (f"(begin case {emit(n[1])} of true -> {name} = {emit(n[2])}; "
                    f"false -> {name} = {emit(n[3])} end, {self.emit(n[4], (name,) + bindings)} end)")
        if op == "pair":
            a, b = self.fresh(), self.fresh()
            return (f"(begin {{{a}, {b}}} = {{{emit(n[1])}, {emit(n[2])}}}, "
                    f"{self.emit(n[3], (a, b) + bindings)} end)")
        if op == "match":
            return f"(begin {n[1]} = {emit(n[2])}, {emit(n[3])} end)"
        if op == "values":
            return "Values"
        if op == "nth":
            return f"hls_vec:nth({emit(n[1])}, {emit(n[2])})"
        if op == "set":
            return f"hls_vec:set({emit(n[1])}, {emit(n[2])}, {emit(n[3])})"
        if op in ("sublist", "slice"):
            arr, start, count = (n[1], n[2], emit(n[3])) if op == "sublist" else (n[2], n[3], str(n[1]))
            descriptor = f"hls_lists:list(hls_nums:{self.word_type}(), {array_size(arr)})"
            method = "sublist" if op == "sublist" else "array_slice"
            return f"hls_lists:{method}({descriptor}, {emit(arr)}, {emit(start)}, {count})"
        if op == "call":
            return f"{self.helper}({emit(n[1])}, {emit(n[2])}, {emit(n[3])})"
        if op == "record":
            record = f"#state{{a = {self.wrap(emit(n[1]), 'u32')}, b = {self.wrap(emit(n[2]), 'u32')}}}"
            return self.wrap(f"({record})#state.{n[3]}")
        raise ValueError(f"unknown node: {n}")


def source(programs):
    exports = ", ".join(f"probe_{i}/3" for i in range(len(programs)))
    text = ["-module(xls_differential_fixture).", f"-export([{exports}]).", "-hls_data(state).",
            "-hls_tags([]).", "-record(state, {a = 0 :: hls_nums:u32(), b = 0 :: hls_nums:u32()})."]
    for i, program in enumerate(programs):
        t = program["type"]
        spec = f"hls_nums:{t}(), hls_nums:{t}(), hls_lists:list(hls_nums:{t}(), 3)"
        emitter = Emitter(t, f"helper_{i}")
        text += [f"-spec helper_{i}({spec}) -> hls_nums:{t}().",
                 f"helper_{i}(X, Y, Values) ->\n    {emitter.emit(program['helper'])}.",
                 f"probe_{i}(X, Y, Values) ->\n    {emitter.emit(program['expression'])}."]
    return "\n\n".join(text) + "\n"


def children(node):
    return [(i, item) for i, item in enumerate(node[1:], 1) if isinstance(item, list)]


def node_type(node):
    if node[0] in ("compare", "andalso", "orelse", "not"):
        return "boolean"
    if node[0] in ("values", "set", "sublist", "slice"):
        return ("array", array_size(node))
    return "word"


def valid(node, bound=0, calls=True):
    if node[0] == "bound":
        return 0 <= node[1] < bound
    if node[0] == "call" and (not calls or array_size(node[3]) != 3):
        return False
    increments = {"let": {2: 1}, "join": {4: 1}, "pair": {3: 2}}.get(node[0], {})
    return all(valid(child, bound + increments.get(index, 0), calls) for index, child in children(node))


def reductions(node):
    """Local, type-preserving reductions; the caller checks whole-tree scope."""
    kind = node_type(node)
    if kind == "word":
        yield ["const", 0]
        yield ["const", 1]
        yield ["var", "X"]
        yield ["var", "Y"]
    if kind == ("array", 3):
        yield ["values"]
    for _, child in children(node):
        if node_type(child) == kind:
            yield child
    if node[0] == "const":
        for value in [0, 1, -1, node[1] // 2]:
            yield ["const", value]
    for index, child in children(node):
        for small in reductions(child):
            yield node[:index] + [small] + node[index + 1:]


def tree_cost(node):
    return 1 + sum(tree_cost(child) for _, child in children(node))


def program_cost(program):
    return (tree_cost(program["expression"]) + tree_cost(program["helper"]),
            len(canonical([program["expression"], program["helper"]])),
            canonical([program["expression"], program["helper"]]))


def program_reductions(program):
    for field in ["expression", "helper"]:
        for tree in reductions(program[field]):
            candidate = {**program, field: tree}
            if valid(tree, calls=field == "expression") and program_cost(candidate) < program_cost(program):
                yield candidate


def coverage(programs):
    counts = Counter()
    def visit(node):
        counts[node[0]] += 1
        if node[0] in ("binary", "compare"):
            counts[f"operator:{node[1]}"] += 1
        for _, child in children(node):
            visit(child)
    for p in programs:
        counts[f"type:{p['type']}"] += 1
        counts["total_program" if p.get("total") else "fallible_program"] += 1
        visit(p["expression"])
        visit(p["helper"])
    return dict(sorted(counts.items()))
