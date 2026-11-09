"""Generate and shrink finite actor programs and schedules, never their semantics."""
from __future__ import annotations

from copy import deepcopy
from typing import Any, Iterator

import compiler_differential_cases as expressions

Program = dict[str, Any]
HORIZON = 64


def generate(seed: int, case_id: int) -> Program:
    """Create independently seeded arithmetic, effect order and eight short segments."""
    rng = expressions.random_for(seed, case_id)
    bad = rng.randrange(256)
    calendar = rng.choice([0, 0xAAAA, 0x9249, 0xFFFF])
    return {"id": case_id, "seed": seed, "initial": rng.randrange(16),
            "bias": rng.randrange(1, 16), "entry": rng.randrange(4),
            "operator": rng.choice(["+", "bxor"]), "reverse": bool(rng.randrange(2)),
            "bad": bad, "threshold": rng.randrange(1, 255),
            "segments": [
                {"reset": True, "ready": calendar, "commands": []},
                {"reset": False, "ready": 0xFFFF, "commands": [[0, 3], [0, 9]]},
                {"reset": False, "ready": calendar, "commands": [[1, 5]]},
                {"reset": False, "ready": 0xAAAA, "commands": [[2, 11], [3, 0]]},
                {"reset": False, "ready": calendar, "commands": [[4, bad ^ 1], [1, 2]]},
                {"reset": False, "ready": calendar, "commands": [[4, bad]]},
                {"reset": False, "ready": 0xFFFF, "commands": [[2, 127]]},
                {"reset": True, "ready": calendar, "commands": [[2, 1], [3, 0]]},
            ]}


def valid(program: Program) -> bool:
    """Accept only the bounded generated grammar and replayable finite schedules."""
    if not isinstance(program, dict):
        return False
    if program.get("operator") not in ("+", "bxor") or not isinstance(program.get("reverse"), bool):
        return False
    if any(type(program.get(k)) is not int or not 0 <= program[k] < 256
           for k in ("initial", "bias", "entry", "bad", "threshold")):
        return False
    segments = program.get("segments")
    if not isinstance(segments, list) or not 1 <= len(segments) <= 16:
        return False
    if not all(isinstance(segment, dict) for segment in segments):
        return False
    if not segments[0].get("reset"):
        return False
    return all(isinstance(s.get("reset"), bool) and type(s.get("ready")) is int
               and 0 <= s["ready"] <= 0xFFFF and isinstance(s.get("commands"), list)
               and len(s["commands"]) <= 8
               and all(isinstance(c, list) and len(c) == 2 and type(c[0]) is int
                       and 0 <= c[0] <= 4 and type(c[1]) is int and 0 <= c[1] < 256
                       for c in s["commands"]) for s in segments)


def source(program: Program) -> str:
    """Render ordinary hls_statem source; BEAM and normal actor lowering execute it."""
    if not valid(program):
        raise ValueError("invalid actor differential program")
    p = program
    order = [("right", 1), ("left", 0)] if p["reverse"] else [("left", 0), ("right", 1)]
    actions = ",\n        ".join(
        f"{{cast, {port}, #output{{port_marker = {index}, value = Next}}}}"
        for port, index in order)
    entry = f'''    Next = hls_nums:wrap(hls_nums:u8(), Cell#cell.value + {p['entry']}),
    Optional = case Next < {p['threshold']} of
        true -> [{{cast, extra, #output{{port_marker = 2, value = Next}}}}];
        false -> []
    end,
    {{Cell#cell{{value = Next}}, [{actions}] ++ Optional}}'''
    phase_bodies = []
    for phase, other in [("quiet", "busy"), ("busy", "quiet")]:
        deferred = (f"{{{phase}, Cell, postpone}}" if phase == "quiet" else
                    f"{{{phase}, Cell#cell{{value = update(Cell#cell.value, Value)}}, consume}}")
        phase_bodies.append(f'''-doc "Handles {phase} entry, deferral, phase changes, ordinary updates and checked failure.".
-spec {phase}(enter | cast, term(), #cell{{}}) -> term().
{phase}(enter, _OldPhase, Cell) ->
{entry};
{phase}(cast, #command{{kind = 0, value = Value}}, Cell) ->
    {deferred};
{phase}(cast, #command{{kind = 1, value = Value}}, Cell) ->
    {{{other}, Cell#cell{{value = update(Cell#cell.value, Value)}}, consume}};
{phase}(cast, #command{{kind = 2, value = Value}}, Cell) ->
    {{{phase}, Cell#cell{{value = update(Cell#cell.value, Value)}}, consume}};
{phase}(cast, #command{{kind = 3}}, Cell) ->
    {{repeat_phase, Cell, consume}};
{phase}(cast, #command{{kind = 4, value = Value}}, Cell) ->
    true = Value =/= {p['bad']},
    %% The failing arm is deliberately unselected on the safe input.
    Next = case Value =:= {p['bad']} of
        true -> true = false, Cell#cell.value;
        false -> Cell#cell.value
    end,
    {{{phase}, Cell#cell{{value = Next}}, consume}}.
''')
    return f'''-module(xls_actor_differential_fixture).
-moduledoc "Seeded finite actor differential fixture; its host termination hook is not lowered.".
-behavior(hls_statem).
-compile({{parse_transform, hls_pack}}).
-hls_data(cell).
-hls_phases([quiet, busy]).
-hls_outputs([left, right, extra]).
-hls_mailbox_capacity(3).
-hls_tags([command, output]).
-export([init/1, quiet/3, busy/3, terminate/3]).
-record(command, {{kind = hls_type:zero() :: hls_nums:u8(),
                  value = hls_type:zero() :: hls_nums:u8()}}).
-record(output, {{port_marker = hls_type:zero() :: hls_nums:u8(),
                 value = hls_type:zero() :: hls_nums:u8()}}).
-record(cell, {{value = hls_type:zero() :: hls_nums:u8()}}).

-doc "Starts in quiet with the seeded bounded value.".
-spec init([]) -> {{ok, quiet, #cell{{}}}}.
init([]) -> {{ok, quiet, #cell{{value = {p['initial']}}}}}.

{''.join(phase_bodies)}
%% Every arithmetic result explicitly follows the unsigned eight-bit contract.
-spec update(hls_nums:u8(), hls_nums:u8()) -> hls_nums:u8().
update(Old, Value) ->
    hls_nums:wrap(hls_nums:u8(), (Old {p['operator']} Value) + {p['bias']}).

-doc "Reports the CPU adapter's last committed state to the test worker.".
-spec terminate(term(), atom(), #cell{{}}) -> ok.
terminate(Reason, Phase, Cell) ->
    xls_actor_differential_oracle ! {{terminated, Reason, Phase, Cell}},
    ok.
'''


def cost(program: Program) -> tuple[int, int, int]:
    """Order reductions by retained segments, commands and numeric schedule values."""
    return (len(program["segments"]), sum(len(s["commands"]) for s in program["segments"]),
            sum(s["ready"] + sum(v for c in s["commands"] for v in c) for s in program["segments"]))


def reductions(program: Program) -> Iterator[Program]:
    """Delete schedule pieces or reduce inputs without modifying the actor or horizon."""
    for i in reversed(range(1, len(program["segments"]))):
        candidate = deepcopy(program)
        del candidate["segments"][i]
        yield candidate
    for i, segment in enumerate(program["segments"]):
        for j in reversed(range(len(segment["commands"]))):
            candidate = deepcopy(program)
            del candidate["segments"][i]["commands"][j]
            yield candidate
        if segment["ready"]:
            candidate = deepcopy(program)
            candidate["segments"][i]["ready"] = 0
            yield candidate
        for j, command in enumerate(segment["commands"]):
            for value in dict.fromkeys([0, 1, command[1] // 2]):
                if value < command[1]:
                    candidate = deepcopy(program)
                    candidate["segments"][i]["commands"][j][1] = value
                    yield candidate
