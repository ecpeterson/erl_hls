"""Feature cases expressed through shared steps; semantic fixtures and oracles stay in Erlang."""
from pathlib import Path
import json
import os
import sys
from regression_steps import Case, Copy, FileText, Rows, pipeline

SCHEDULES = ((1, 1), (2, 1), (3, 2))
TYPE_ERROR = r"TypeInferenceError|[Tt]ype[Mm]ismatch|[Tt]ype mismatch|[Ss]ize mismatch"

def bench(c: Case, name: str) -> Path:
    """Name a checked-in testbench without copying or changing its oracle."""
    return c.root / "test/rtl" / (name + ".sv")


def scalar(c: Case, name: str, *, top: str = "probe", module: str = "probe", tb: str | None = None,
           source: str | None = None) -> None:
    """Interpret, compile and simulate a generated scalar fixture."""
    c.interpret(source or name + ".x")
    c.convert(name, top, source)
    c.codegen(name, module=module)
    c.simulate(name, tb or name + "_tb", [c.path(name + ".v"), c.path((tb or name + "_tb") + ".sv")])


def vector_case(c: Case, name: str, module: str, tb: str, defines: list, *, timeout: float = 300) -> None:
    """Run one Erlang-owned vector corpus through interpreter/JIT and combinational RTL."""
    c.interpret(name + ".x")
    c.convert(name, "probe")
    c.codegen(name, module=module)
    c.simulate(name, tb, [bench(c, tb), c.path(name + ".v")], flags=defines, timeout=timeout)


def service_probe(c: Case) -> None:
    """Exercise the generated scalar suite's framed service with its original request/reply files."""
    c.convert("service", "Top")
    c.codegen("service", flags=pipeline(2))
    c.simulate("service", "logical_service_tb", [bench(c, "logical_service_tb"), c.path("service.v")],
        arguments=["+requests=" + str(c.path("requests.mem")), "+replies=" + str(c.path("replies.mem"))])


def source_context(c: Case) -> None:
    """Check both include/macro configurations through the generated source witnesses."""
    c.generate("hls_source_dslx")
    for configuration in ("narrow", "wide"):
        c.interpret(f"source_{configuration}.x")


def phase_values(c: Case) -> None:
    """Compare baseline and candidate phase-specialization witnesses."""
    c.generate("xls_phase_values_dslx")
    for name in ("phase_baseline", "phase_candidate"):
        c.interpret(name + ".x")


def entry_outcomes(c: Case) -> None:
    """Retain all entry/storage interpreter witnesses and both RTL outcome benches."""
    c.compile(); c.fixture("entry_outcomes")
    for name in ("xls_entry_outcome", "xls_entry_branch", "xls_entry_reduction", "xls_entry_storage", "known_bits"):
        c.interpret(name + ".x")
    for name, top in (("xls_entry_outcome", "entry_probe"), ("xls_entry_branch", "entry_cycle_probe")):
        c.convert(name, top); c.codegen(name, module=top)
        c.simulate(name, name + "_tb", [c.path(name + "_tb.sv"), c.path(name + ".v")])


def type_shapes(c: Case) -> None:
    """Check nested shape lowering and its explicit routing assertion rejection."""
    c.generate("xls_type_shape_dslx")
    scalar(c, "shape")
    c.convert("nested", "probe", optimize=False)
    c.convert("nested_mismatch", "probe", rejection=r"const_assert! failure")


def patterns(c: Case) -> None:
    """Retain runtime patterns, negative constant tails and destructured reduction conversion."""
    c.generate("xls_patterns_dslx")
    c.interpret(c.root / "priv/xls/lib/hls_patterns.x")
    scalar(c, "patterns")
    for name in ("empty_tail", "overlong_tail"):
        c.convert(name, "probe", rejection=r"const_assert! failure")
    c.convert("list_reduction", "Service")


def names(c: Case) -> None:
    """Check warning-free unused names, function/service conversion and generated RTL ports."""
    c.compile(); c.fixture("names")
    c.interpret("unused.x", warnings=True)
    for name in ("names", "gs"):
        c.interpret(name + ".x"); c.convert(name, "probe")
    for name in ("ordinary", "gs"):
        c.convert(name + ".service", "Service", name + ".x", optimize=False)
    c.codegen("names", module="probe")
    c.simulate("names", "names_tb", [c.path("names.v"), c.path("names_tb.sv")])


def integer_arithmetic(c: Case) -> None:
    """Compare all original arithmetic widths and static-expression/failure semantics against BEAM."""
    c.generate("xls_integer_dslx")
    for width in (1, 3, 8, 9, 16, 32, 64):
        for sign in ("u", "s"):
            name = f"{sign}{width}"
            vector_case(c, name, "integer_probe", "xls_integer_tb", [f"-DINTEGER_WIDTH={width}",
                FileText(c.path(name + ".count"), "-DINTEGER_COUNT="),
                '-DINTEGER_VECTORS="' + str(c.path(name + ".mem")) + '"'])
    c.interpret("static_integer.x")
    c.convert("static_integer", "probe")
    c.codegen("static_integer", module="static_integer_probe")
    c.simulate("static_integer", "xls_static_integer_tb",
        [bench(c, "xls_static_integer_tb"), c.path("static_integer.v")],
        flags=[FileText(c.path("static_integer.count"), "-DSTATIC_INTEGER_COUNT="),
            '-DSTATIC_INTEGER_VECTORS="' + str(c.path("static_integer.mem")) + '"'],
        completion="PASS: static integer BEAM/optimized-RTL expressions and failure flags")


def integer_shifts(c: Case) -> None:
    """Use the fixture writer's variant table, without repeating its signedness/width matrix."""
    c.generate("xls_shift_dslx")
    c.interpret(c.root / "priv/xls/lib/hls_integer.x")
    def expand(row: list[str]) -> list:
        """Produce one complete shift pipeline from the generated corpus dimensions."""
        name, width, count_width, count = row
        child = Case(c.root, c.xls, c.stage)
        vector_case(child, name, "shift_probe", "xls_shift_tb", [f"-DSHIFT_WIDTH={width}",
            f"-DSHIFT_COUNT_WIDTH={count_width}", f"-DSHIFT_CASES={count}",
            '-DSHIFT_VECTORS="' + str(c.path(name + ".mem")) + '"'])
        return child.steps
    c.steps.append(Rows(c.path("variants.txt"), 4, expand))


def comparisons(c: Case) -> None:
    """Compare mixed integer widths and the framed actor, retaining every original pair."""
    c.generate("xls_comparison_dslx")
    for left, right in ((1, 1), (3, 8), (8, 8), (8, 9), (32, 8), (64, 32), (65, 64), (128, 65)):
        name = f"cmp_{left}_{right}"
        vector_case(c, name, "comparison_probe", "xls_comparison_tb", [f"-DLEFT_WIDTH={left}",
            f"-DRIGHT_WIDTH={right}", FileText(c.path(name + ".count"), "-DCOMPARISON_COUNT="),
            '-DCOMPARISON_VECTORS="' + str(c.path(name + ".mem")) + '"'])
    service_probe(c)


def serial(c: Case) -> None:
    """Check wrapping counter vectors and their framed service at the original widths."""
    c.generate("hls_serial_dslx")
    for width in (1, 3, 8, 9, 32, 64, 65):
        name = f"serial{width}"
        vector_case(c, name, "serial_probe", "hls_serial_tb", [f"-DSERIAL_WIDTH={width}",
            FileText(c.path(name + ".count"), "-DSERIAL_COUNT="),
            '-DSERIAL_VECTORS="' + str(c.path(name + ".mem")) + '"'])
    service_probe(c)


def collections(c: Case) -> None:
    """Keep constant-wiring assertions plus signed/unsigned collection vector simulation."""
    c.generate("xls_collection_dslx")
    c.interpret(c.root / "priv/xls/lib/hls_lists.x")
    c.interpret("constant.x"); c.convert("constant", "constant_probe"); c.codegen("constant", module="constant_probe")
    c.yosys("constant", f'read_verilog -sv "{c.path("constant.v")}"; hierarchy -top constant_probe; proc; opt; check -assert; select -assert-none t:*')
    for width in (8, 32, 64):
        for sign in ("u", "s"):
            name = f"{sign}{width}"
            vector_case(c, name, "collection_probe", "xls_collection_tb", [f"-DCOLLECTION_WIDTH={width}",
                FileText(c.path(name + ".count"), "-DCOLLECTION_COUNT="),
                '-DCOLLECTION_VECTORS="' + str(c.path(name + ".mem")) + '"'], timeout=60)


def helpers(c: Case) -> None:
    """Retain helper SAT equivalence, typed literal contexts, nested records and all negative cases."""
    c.generate("xls_helpers_dslx"); c.interpret("helpers.x")
    for top in ("factored", "inline"):
        c.convert(top, top, "helpers.x"); c.codegen(top, module=top)
    c.simulate("helpers", "helpers_tb", [c.path("helpers_tb.sv"), c.path("factored.v"), c.path("inline.v")])
    c.yosys("equivalence", f'read_verilog "{c.path("factored.v")}" "{c.path("inline.v")}"; '
        'miter -equiv -flatten factored inline helper_equivalence; prep -top helper_equivalence; '
        'sat -verify -prove trigger 0 -show-inputs -show-outputs', environment="YOSYS")
    for name in ("wrong_argument", "wrong_result", "wrong_join"):
        c.convert(name, "root", rejection=r"[Tt]ype[Mm]ismatch|[Tt]ype mismatch|[Ss]ize mismatch")
    c.erl("ok = xls_literal_types_dslx:write(hd(init:get_plain_arguments())), halt().", name="literal-fixtures")
    scalar(c, "literal_context", top="run", module="literal_context")
    for name in ("literal_conflicting_uses", "literal_existing_value", "literal_record_existing_value", "literal_record_conflicting_uses"):
        c.convert(name, "root", rejection=TYPE_ERROR)
    c.erl("ok = hls_nested_records_dslx:write(hd(init:get_plain_arguments())), halt().", name="nested-fixtures")
    scalar(c, "nested_records", top="nested_transition", module="nested_records")
    for kind in ("nested", "expression_case", "empty_case", "field_access"):
        c.interpret("nested_wrong_" + kind + ".x", compare="none", rejection=r"TypeInferenceError|[Tt]ype[Mm]ismatch|[Tt]ype mismatch")


def control_failures(c: Case) -> None:
    """Check first failures, constant rejection and stalled service replies across three schedules."""
    c.generate("xls_control_failure_dslx"); c.interpret("control.x")
    for kind in ("case", "if", "div", "rem", "nth", "set", "slice"):
        c.convert(f"bad_{kind}_init", "bits_from_report", rejection=r"const_assert! failure.*INITIAL_")
    for top in ("control_probe", "Top"):
        c.convert(top, top, "control.x")
    c.codegen("control_probe", module="control_probe")
    for stages, interval in SCHEDULES:
        name = f"service-p{stages}-ii{interval}"
        c.codegen(name, source="Top", module="control_service", flags=pipeline(stages, interval))
        c.structure(name, "control_service", [c.path(name + ".v")])
        c.simulate(name, "xls_control_failure_tb", [bench(c, "xls_control_failure_tb"), c.path("control_probe.v"), c.path(name + ".v")],
            flags=["-I", c.stage])


def float_arithmetic(c: Case) -> None:
    """Keep scalar/collection conversion, BEAM-vector RTL, actor stalls and malformed float rejection."""
    c.generate("hls_float_dslx")
    for width, initial in ((16, "16'h3e00"), (32, "32'h3fc00000"), (64, "64'h3ff8000000000000")):
        name = f"float{width}"
        c.interpret(name + ".x"); c.interpret(name + "_actor.x")
        c.convert(name + "_slice", "slice", name + ".x"); c.codegen(name + "_slice")
        c.convert(name + "_probe", "probe", name + ".x"); c.codegen(name + "_probe", module="float_probe")
        c.simulate(name + "_probe", "hls_float_probe_tb", [bench(c, "hls_float_probe_tb"), c.path(name + "_probe.v")],
            flags=["-I", c.stage, f"-DFLOAT_WIDTH={width}", f'-DFLOAT_VECTORS="{name}.svh"'])
        c.convert(name + "_actor", "Top"); c.codegen(name + "_actor", module="float_actor", flags=pipeline(3))
        c.structure(name + "_actor", "float_actor", [c.path(name + "_actor.v")])
        c.simulate(name + "_actor", "hls_float_actor_tb", [bench(c, "hls_float_actor_tb"), c.path(name + "_actor.v")],
            flags=["-I", c.stage, f"-DFLOAT_WIDTH={width}", f"-DFLOAT_INITIAL={initial}", f'-DFLOAT_ACTOR_VECTORS="{name}_actor.svh"'])
    for name in ("integer_operator", "wrong_precision", "integer_operand"):
        c.convert(name, "probe", rejection=r"TypeInferenceError|TypeMismatch|Type mismatch|type mismatch|type error")


def binary(c: Case) -> None:
    """Keep bit syntax/codecs, a wires-only assertion, and live packed-sample observation."""
    c.imports = ("lib", "debug")
    c.compile(); c.fixture("binary")
    c.interpret(c.root / "priv/xls/lib/hls_bits.x")
    for name, top in (("binary", "probe"), ("binary_codecs", "codec_probe")):
        scalar(c, name, top=top, module=top)
    c.convert("wires", "wire_probe", "binary.x"); c.codegen("wires", module="wire_probe")
    c.yosys("wires", f'read_verilog "{c.path("wires.v")}"; hierarchy -top wire_probe; proc; opt; check -assert; select -assert-none t:*')
    for name, top, stages, interval in (("packed_samples", "Top", 3, 2),
            ("hls_debug_observer", "Observer", 2, 1), ("hls_debug_server", "DebugServer", 3, 2)):
        if name != "packed_samples":
            c.steps.append(Copy(c.root / "priv/xls/debug", name + ".x", c.stage))
        c.convert(name, top); c.codegen(name, flags=pipeline(stages, interval, flop=False))
    c.structure("service", "__packed_samples__Top_0_next", [c.path("packed_samples.v")])
    c.python("packed-samples", "test_packed_samples.py", c.stage, "--stage", c.path("live"))


def application_frames(c: Case) -> None:
    """Exercise all frame families and the ordinary service at the original schedules."""
    c.imports = ("lib", "fabric")
    c.interpret(c.root / "priv/xls/lib/axis.x")
    for top, defines in (("RawTop", []), ("ReservedTop", ["-DRESERVED"]),
                         ("EndpointTop", ["-DROUTED"]), ("DebugTop", [])):
        c.convert(top, top, c.root / "test_data/application_frames_rtl.x")
        for stages, interval in SCHEDULES:
            name = f"{top}-p{stages}-ii{interval}"
            c.codegen(name, source=top, module="application_frames", flags=pipeline(stages, interval))
            c.structure(name, "application_frames", [c.path(name + ".v")])
            if top != "DebugTop":
                c.simulate(name, "application_frames_tb", [bench(c, "application_frames_tb"), c.path(name + ".v")], flags=defines)
    c.compile()
    c.fixture("application_frames")
    c.convert("application_service", "Top")
    for stages, interval in SCHEDULES:
        name = f"service-p{stages}-ii{interval}"
        c.codegen(name, source="application_service", module="application_service", flags=pipeline(stages, interval))
        c.structure(name, "application_service", [c.path(name + ".v")])
        c.simulate(name, "application_service_tb", [bench(c, "application_service_tb"), c.path(name + ".v")])
    c.python("frame-backpressure-debug", "test_topology_debug_integration.py",
        "--top", "application_frames", "--stage", c.path("debug"), c.path("DebugTop-p2-ii1.v"))


def direct_actor_codegen(c: Case) -> None:
    """Check actor observation emission, committed-state behavior and compiler-bound ports."""
    c.imports = ("lib", "fabric"); c.stage_import = True
    c.generate("xls_actor_observation_tests")
    for name in ("hls_dense_statem_fixture", "debug_scalar", "debug_rectangle", "debug_commit"):
        c.convert(name, "Top"); c.codegen(name, module=name, flags=pipeline(2))
    c.simulate("commit", "hls_actor_observation_tb", [bench(c, "debug/hls_actor_observation_tb"), c.path("debug_commit.v")],
        flags=["-I", c.stage])
    c.python("observation-ports", "check_actor_observation_ports.py", c.stage)


def direct_admission(c: Case) -> None:
    """Retain capacity checks, nine admission schedules, bounded formal and connected debug."""
    c.imports = ("lib", "fabric"); c.stage_import = True
    c.compile(); c.fixture("direct_admission")
    c.interpret("large_mailbox_64.x", compare="none")
    c.interpret("large_mailbox_255.x", compare="none", flags=("--test_filter=^$",))
    for kind, source, top, module, tb in (
            ("service", "ordered_egress_actor.x", "Service", "direct_admission_service", "direct_admission_tb"),
            ("d1", "d1/ordered_egress_topology.x", "Top", "__ordered_egress_topology__Top_0_next", "ordered_egress_topology_tb"),
            ("d2", "d2/ordered_egress_topology.x", "Top", "__ordered_egress_topology__Top_0_next", "ordered_egress_topology_tb")):
        c.convert(kind, top, source)
        for stages, interval in SCHEDULES:
            name = f"{kind}-p{stages}-ii{interval}"
            c.codegen(name, source=kind, module=module, flags=pipeline(stages, interval))
            c.structure(name, module, [c.path(name + ".v")])
            c.simulate(name, tb, [bench(c, tb), c.path(name + ".v")], timeout=60)
    c.python("admission-formal", "test_direct_admission_formal.py", "--stage", c.path("formal"),
        *(c.path(f"service-p{stages}-ii{interval}.v") for stages, interval in SCHEDULES))
    c.python("admission-debug", "test_topology_debug_integration.py", "--yosys", os.environ.get("ERL_HLS_YOSYS", "yosys"),
        "--top", "__ordered_egress_topology__Top_0_next", "--stage", c.path("debug"), c.path("d1-p2-ii1.v"))


def initialization(c: Case) -> None:
    """Retain constant rejection independent of selected entry and initialized service/topology RTL."""
    c.imports = ("lib", "fabric"); c.stage_import = True
    c.generate("xls_init_dslx")
    for kind in ("gs", "statem"):
        c.interpret(f"init_{kind}.x")
        c.convert("bad_" + kind, "bits_from_report", rejection=r"const_assert! failure.*INITIAL_")
    for fixture, top, tb in (("gs", "FrameTop", "xls_init_gs_tb"), ("direct", "Top", "xls_init_topology_tb")):
        c.convert("init_" + fixture, top)
        for stages in (1, 2):
            name = f"init_{fixture}_{stages}"
            c.codegen(name, source="init_" + fixture, module="init_" + fixture,
                flags=pipeline(stages) + ("--ram_configurations=",))
            wrapper = "init_direct_wrapper" if fixture == "direct" else top
            sources = [c.path(name + ".v")] + ([c.path(wrapper + ".v")] if fixture == "direct" else [])
            c.simulate(name, tb, [bench(c, tb), *sources], flags=["-I", c.stage, "-DINIT_TOP=" + wrapper])


def framed_service(c: Case, fixture: str, source: str, artifact: str, tb: str,
                   schedules: tuple[tuple[int, int], ...]) -> None:
    """Generate one Erlang service and retain its production compiler adapter plus public-port benches."""
    c.compile()
    c.fixture(fixture)
    c.library("lib")
    for stages, interval in schedules:
        name = f"p{stages}-ii{interval}"
        rtl = c.compiled(name, source, artifact, stages, interval)
        c.structure(name, "__" + Path(source).stem + "__Top_0_next", [rtl])
        c.simulate(name, tb, [bench(c, tb), rtl])


def deferred_replies(c: Case) -> None:
    """Retain iterative draining and delayed replies under both public-port schedules."""
    framed_service(c, "deferred_replies", "batch.x", "deferred_server", "deferred_server_tb", ((2, 2), (3, 3)))


def service_contracts(c: Case) -> None:
    """Retain reply-service wire contracts across all three pipeline schedules."""
    framed_service(c, "service_contracts", "service.x", "reply_service", "service_contracts_tb", SCHEDULES)


def logical_types(c: Case) -> None:
    """Check shared codecs, wires-only conversion, service schedules and both topology forms."""
    c.compile()
    c.fixture("logical_types")
    c.interpret("codecs.x"); c.interpret("struct_codecs.x")
    c.convert("codecs", "probe"); c.codegen("codecs", module="probe")
    c.simulate("codecs", "logical_codecs_tb", [c.path("codecs.v"), bench(c, "logical_codecs_tb")],
        arguments=["+vectors=" + str(c.path("codecs.mem"))])
    c.convert("wires", "wire_probe", "codecs.x"); c.codegen("wires", module="wire_probe")
    c.yosys("wires", f'read_verilog "{c.path("wires.v")}"; hierarchy -top wire_probe; proc; opt; check -assert; select -assert-none t:*')
    c.library("lib")
    for stages, interval in SCHEDULES:
        name = f"p{stages}-ii{interval}"
        rtl = c.compiled(name, "service.x", "logical_service", stages, interval)
        c.structure(name, "__service__Top_0_next", [rtl])
        c.simulate(name, "logical_service_tb", [bench(c, "logical_service_tb"), rtl],
            arguments=["+requests=" + str(c.path("requests.mem")), "+replies=" + str(c.path("replies.mem"))])
    c.library("fabric")
    for fixture in ("direct", "family"):
        name = "dense_" + fixture
        rtl = c.compiled(name + "-build", name + ".x", name, 2)
        sources = [rtl, c.path(name + "_wrapper.v")]
        c.structure(name, name + "_wrapper", sources)
        c.simulate(name, "logical_topology_tb", [bench(c, "logical_topology_tb"), *sources],
            flags=["-I", c.stage, "-DDENSE_TOP=" + name + "_wrapper"])


def reduction_dslx(c: Case) -> None:
    """Keep all reduction semantic snippets, signed masks, debug and ordinary failure conversion."""
    c.compile(); c.fixture("reduction_dslx")
    for name in ("reduction", "failure", "mask", "mask_debug", "signed_mask"):
        c.interpret(name + ".x"); c.convert(name, "Top", optimize=False)


def statem_gathers(c: Case) -> None:
    """Check ordered gathers, continuation sites and debug through the ordinary actor."""
    c.generate("xls_statem_gather_dslx"); c.library("lib", "fabric")
    c.imports = (); c.stage_import = True
    for name in ("statem_gather", "statem_gather_sites", "statem_gather_debug"):
        c.interpret(name + ".x", override=True)


def statem_replies(c: Case) -> None:
    """Retain reply/event semantics and singleton/topology public ports at both schedules."""
    c.generate("hls_statem_reply_dslx"); c.library("lib", "fabric")
    c.imports = (); c.stage_import = True
    for name in ("statem_direct", "statem_events", "statem_reduction_replies", "hls_reply"):
        c.interpret(name + ".x", override=True)
    for kind in ("direct", "topology"):
        top = "statem_topology_wrapper" if kind == "topology" else "__statem_direct__Top_0_next"
        for stages in (2, 3):
            name = f"{kind}-p{stages}"
            rtl = c.compiled(name, "statem_" + kind + ".x", "statem", stages, flags=("--ram-configurations", ""))
            sources = [rtl] + ([c.path("statem_topology_wrapper.v")] if kind == "topology" else [])
            c.structure(name, top, sources)
            tb = "statem_reply_" + kind + "_tb"
            c.simulate(name, tb, [bench(c, tb), *sources])


def mixed_topology(c: Case) -> None:
    """Preserve requested placements and both codegen schedules in the connected topology driver."""
    if not c.placements or any(p not in ("direct", "ingress_direct") for p in c.placements):
        raise ValueError("placements must be direct or ingress_direct")
    c.compile()
    for placement in c.placements:
        child = Case(c.root, c.xls, c.path(placement), imports=("lib", "fabric"), stage_import=True)
        child.fixture("mixed_topology", placement)
        child.convert("topology", "Top", "mixed_topology.x")
        actor_test = "mixed_direct" if placement == "direct" else "ingress_direct"
        for stages in (2, 3):
            name = f"topology_{stages}"
            child.codegen(name, source="topology", module="mixed_topology", flags=pipeline(stages))
            child.python(f"p{stages}-debug", "test_topology_debug_integration.py", "--yosys", os.environ.get("YOSYS", "yosys"),
                "--top", "mixed_topology_wrapper", "--stage", child.path(f"p{stages}"),
                "--actor-projection", child.path("actors.json"), "--actor-test", actor_test,
                child.path(name + ".v"), child.path("mixed_topology_wrapper.v"))
        c.steps.extend(child.steps)


def selection_equivalence(c: Case) -> None:
    """Compare indexed/direct/early selectors for all input bits at both retained fan-ins."""
    c.steps.append(Copy(c.root / "test_data", "xls_selection.x", c.stage))
    for width in (19, 22):
        for form in ("indexed", "direct", "early"):
            name = f"{form}{width}"
            c.convert(name, name, "xls_selection.x")
            c.codegen(name, module=name)
        for form in ("direct", "early"):
            left, right = f"indexed{width}", f"{form}{width}"
            c.yosys(f"equivalence-{right}",
                f'read_verilog {json.dumps(str(c.path(left + ".v")))} {json.dumps(str(c.path(right + ".v")))}; '
                f'miter -equiv -flatten {left} {right} miter; prep -top miter; '
                'sat -verify -prove trigger 0 -show-inputs -show-outputs')


def state_updates(c: Case) -> None:
    """Check 8,192 addressed-state replies with stalls/reset; retain a diagnostic IR census."""
    c.steps.append(Copy(c.root / "test_data", "xls_state_updates.x", c.stage))
    c.steps.append(Copy(c.root / "test/rtl", "xls_state_updates_tb.sv", c.stage))
    c.convert("state_updates", "Rows", "xls_state_updates.x")
    c.codegen("state_updates", module="state_updates", flags=pipeline(2))
    c.simulate("state_updates", "xls_state_updates_tb",
        [c.path("xls_state_updates_tb.sv"), c.path("state_updates.v")],
        timeout=120, completion="PASS: 8192 replies")
    c.command("state-census", [sys.executable, c.root / "tools/xls_ir_census.py",
        c.path("state_updates.opt.ir"), "--output", c.path("state_updates.census.json")],
        products=(c.path("state_updates.census.json"),))


def telemetry(c: Case) -> None:
    """Compile the shipped two-actor example bundle once and compare its stalled/reset RTL to BEAM."""
    c.generate("telemetry_example_fixture")
    rtl = c.path("compiled/telemetry.v")
    c.command("telemetry-bundle", [sys.executable, c.root / "priv/tools/compile_source_build.py",
        c.xls, c.path("bundle"), "--output", c.path("compiled"), "--cache", c.path("cache")],
        products=(rtl,), timeout=900)
    c.structure("telemetry", "telemetry_top", [rtl])
    c.simulate("telemetry", "telemetry_example_tb", [bench(c, "telemetry_example_tb"), rtl],
        flags=["-I", c.stage], arguments=["+vectors=" + str(c.stage)], timeout=60,
        completion="PASS: telemetry CPU/RTL windows, malformed ingress, stalls and reset")
