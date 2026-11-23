"""Run two fresh Phi memory incarnations through current domain streams and public RTL ports."""
import phi_tool_paths  # Resolve the application's shared external-tool helpers.
import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path
from backend_commands import digest, run
from backend_paths import ROOT, erlang_paths
from domain_endpoint_network_witness import compile_adapter as compile_network_adapter
from test_protocol_repetition import compare


def adapter_source(bundle: Path, stage: Path) -> Path:
    """Bind emitted crossing IDs and global observation addresses without altering hardware."""
    metadata = json.loads((bundle / "fixture.json").read_text())
    assert metadata["execution"] == "same_clock_local_composition"
    assert metadata["physical_board_image"] is False
    assert [domain["index"] for domain in metadata["domains"]] == [0, 1]
    template = ROOT / "apps/hls_phi/test/rtl/phi_domain_repetition_sim.cpp.in"
    text = template.read_text().replace("@@FRAME_WORDS@@", str(metadata["frame_words"]))
    text = text.replace("@@CROSSINGS@@", "\n".join(
        f"crossings.emplace_back(CROSSING(ch_{channel['index']}),{channel['index']});"
        for channel in metadata["channels"]))
    observations = []
    if metadata["inspection"] == "process":
        for domain in metadata["domains"]:
            index = domain["index"]
            foreign = next(row["actors"][0] for row in metadata["domains"] if row["index"] != index)
            actors = ",".join(map(str, domain["actors"]))
            observations.append(
                f"inspections.emplace_back(core.domain_{index}_inspect_address,"
                f"core.domain_{index}_inspect_incarnation,core.domain_{index}_app_inspect_value,"
                f"std::vector<unsigned>{{{actors}}},{foreign},"
                f'directory+"/domain{index}_inspection.control");')
    else:
        assert metadata["inspection"] == "none"
    text = text.replace("@@INSPECTIONS@@", "\n".join(observations))
    assert "@@" not in text
    source = stage / "phi-domain-repetition.cpp"
    source.write_text(text)
    for name in ("framed_fifo_endpoint.h", "framed_fifo_stream.h", "framed_fifo_control.h"):
        shutil.copyfile(ROOT / "test/rtl" / name, stage / name)
    return source


def compile_adapter(bundle: Path, compiled: Path, stage: Path) -> Path:
    """Compile only the finite public-pin adapter around already compiled source-build RTL."""
    manifest = json.loads((bundle / "source-build.json").read_text())
    rtl = [compiled / name for name in dict.fromkeys(
        name for unit in manifest["units"] for name in unit["rtl"])]
    assert all(path.is_file() for path in rtl)
    source = adapter_source(bundle, stage)
    run(["verilator", "--cc", "--exe", "--build", "--top-module", "protocol_domains_stream",
         "--Mdir", stage / "obj_dir", "-j", "1", "-Wno-fatal", "-CFLAGS", "-std=c++17",
         "-o", "simulation", *rtl, source], stage, "verilator", timeout=1800)
    binary = stage / "obj_dir/simulation"
    inputs = [*rtl, source, *stage.glob("*.h"), bundle / "source-build.json",
              bundle / "interface.etf", bundle / "fixture.etf", bundle / "fixture.json",
              bundle / "channel_management/interface.etf",
              ROOT / "apps/hls_phi/test/rtl/phi_domain_repetition_sim.cpp.in"]
    inputs.extend(bundle.glob("domain_*/domain/interface.etf"))
    binary.with_suffix(".json").write_text(json.dumps({
        "binary_sha256": digest(binary), "bundle": str(bundle),
        "inputs": {str(path): digest(path) for path in inputs}}, indent=2) + "\n")
    return binary


def reuse(binary: Path) -> tuple[Path, Path]:
    """Permit host-only corrections without repeating immutable successful hardware compilation."""
    metadata = json.loads(binary.with_suffix(".json").read_text())
    assert digest(binary) == metadata["binary_sha256"]
    for path, expected in metadata["inputs"].items():
        assert digest(Path(path)) == expected, path
    return binary, Path(metadata["bundle"])


def runtime_inputs(paths: list[Path], independent: bool = False) -> dict[str, str]:
    """Retain the exact compiled host code used by this independent witness attempt."""
    modules = ("phi_domain_repetition_live", "hls_recovery_stream_live", "phi_repetition_memory",
               "hls_domain", "hls_domain_instance", "hls_domain_fabric", "hls_domain_wire",
               "hls_domain_channel_fabric", "hls_domain_channel_instance", "hls_fabric")
    if independent:
        modules += ("hls_domain_endpoint_pair", "hls_domain_endpoint_wire", "hls_type", "hls_nums")
    result = {}
    for module in modules:
        matches = [path / (module + ".beam") for path in paths if (path / (module + ".beam")).is_file()]
        if not matches:
            raise FileNotFoundError(f"Compile the selected host profile before this witness: {module}")
        for path in matches:
            result[str(path)] = digest(path)
    return result


def retire_simulator(child: subprocess.Popen) -> None:
    """Stop and reap an owned simulator, escalating after a bounded graceful wait."""
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=5)


def witness(binary: Path, bundle: Path, native: Path, stage: Path, profile: str,
            extra_ebin: list[Path], previous: Path | None, network: Path | None = None,
            namespace: int = 1) -> None:
    """Compare both lifetimes to one retained BEAM oracle, including stale transport exclusions."""
    metadata = json.loads((bundle / "fixture.json").read_text())
    expected = json.loads(native.read_text())
    native_hash = digest(native)
    paths = [*extra_ebin, *erlang_paths(profile)]
    host_hashes = runtime_inputs(paths, network is not None)
    binary_record = binary.with_suffix(".json")
    binary_hashes = json.loads(binary_record.read_text())["inputs"]
    live = stage / "live"
    live.mkdir()
    with (live / "simulation.log").open("x") as log:
        child = subprocess.Popen([str(binary), str(live)], stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            last_fifo = "endpoint1_management_rx" if network else "domain1_application_rx"
            while not (live / last_fifo).exists():
                if child.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("Phi domain adapter did not create its public FIFOs")
                time.sleep(.02)
            expression = "[Bundle,Stage]=init:get_plain_arguments(),ok=phi_domain_repetition_live:run(Bundle,Stage),halt()."
            extra = [bundle, live]
            if network:
                expression = ("[Bundle,Stage,Network,Namespace]=init:get_plain_arguments(),"
                    "ok=phi_domain_repetition_live:run(Bundle,Stage,#{mode=>independent_endpoints,"
                    "network_bundle=>Network,namespace=>list_to_integer(Namespace)}),halt().")
                extra += [network, str(namespace)]
            run(["erl", "+S", "2:2", "-noshell", "-pa", *paths, "-eval", expression,
                 "-extra", *extra], live, "host", timeout=580)
            assert child.wait(timeout=10) == 0
        finally:
            retire_simulator(child)
    assert "PASS Phi domain repetition:" in (live / "simulation.log").read_text()
    actual = json.loads((live / "result.json").read_text())
    transport = json.loads((live / "transport.json").read_text())
    assert actual["passed"] and actual["descriptors_closed"] and actual["old_pids_terminal"]
    assert len(actual["incarnations"]) == 2
    recovery = actual["recovery"]
    assert recovery["one_for_all"] and recovery["outputs_retirement_frontier_closed"]
    assert recovery["old_actor_alive_until_delivery_resumed"] and recovery["source_failure_code"] > 0
    assert recovery["held_received"] < recovery["held_frontier"] <= recovery["received_after_retirement"]
    assert recovery["old_endpoints"] == 3 * metadata["width"]
    for incarnation in actual["incarnations"]:
        compare({**incarnation, "descriptors_closed": True}, expected, metadata["width"])
    first, second = actual["incarnations"]
    assert all(b > a for a, b in zip(first["domain_incarnations"], second["domain_incarnations"]))
    assert all(b > a for a, b in zip(first["channel_generations"], second["channel_generations"]))
    assert len(transport["channels"]) == len(metadata["channels"])
    assert all(row["stale_data_dropped"] and row["stale_credit_dropped"] for row in transport["channels"])
    assert bool(transport["inspection"]) == (metadata["inspection"] == "process")
    if network:
        check_network(actual, transport, metadata, namespace)
    matched = None
    if previous:
        baseline = json.loads(previous.read_text())
        assert baseline["passed"] and baseline["native_sha256"] == native_hash
        assert baseline["width"] == metadata["width"] and baseline["split"] == metadata["split"]
        assert baseline["inspection"] != metadata["inspection"] or bool(baseline.get("network")) != bool(network)
        for before, after in zip(baseline["result"]["incarnations"], actual["incarnations"]):
            compare({**after, "descriptors_closed": True}, before, metadata["width"])
        matched = {"result": str(previous), "sha256": digest(previous)}
    assert digest(native) == native_hash
    assert all(digest(Path(path)) == expected_hash for path, expected_hash in host_hashes.items())
    assert all(digest(Path(path)) == expected_hash for path, expected_hash in binary_hashes.items())
    result = {"passed": True, "width": metadata["width"], "split": metadata["split"],
        "inspection": metadata["inspection"], "native": str(native), "native_sha256": native_hash,
        "binary": str(binary), "binary_sha256": digest(binary), "binary_manifest_sha256": digest(binary_record),
        "runtime_inputs": host_hashes,
        "result": actual, "transport": transport, "matched_observation_run": matched,
        "evidence": "Finite ordinary-BEAM/production-runtime/public-RTL witness. Same-clock composition; no independent-board, CDC, timing or sustained-throughput qualification."}
    if network:
        result.update(network=str(network), endpoint_namespace=namespace,
            evidence="Finite ordinary-BEAM/production-runtime/public-RTL witness with independent sampled clocks, "
                     "two domain incarnations and a capacity-one atomic carrier model in each direction. "
                     "No physical carrier, CDC circuit, timing or sustained-throughput qualification.")
    (stage / "result.json").write_text(json.dumps(result, indent=2) + "\n")


def check_network(actual: dict, transport: dict, metadata: dict, namespace: int) -> None:
    """Match both host full bindings to independently captured wire identities and all sixteen native stale drops."""
    assert actual["endpoint_namespace"] == namespace
    assert actual["evidence"] == "finite_independent_endpoint_public_stream_witness"
    channels = metadata["channels"]
    assert len(channels) == 8 and len({row["index"] for row in channels}) == 8
    assert {row["index"] for row in transport["channels"]} == {row["index"] for row in channels}
    fields = ("namespace", "generation", "source_incarnation", "destination_incarnation")
    for incarnation in actual["incarnations"]:
        bindings = incarnation["endpoint_bindings"]
        assert [row["index"] for row in bindings] == [row["index"] for row in channels]
        assert len(incarnation["domain_incarnations"]) == 2
        for index, (binding, channel) in enumerate(zip(bindings, channels)):
            assert binding["namespace"] == namespace and binding["generation"] == incarnation["channel_generations"][index]
            assert binding["source_incarnation"] == incarnation["domain_incarnations"][channel["source_domain"]]
            assert binding["destination_incarnation"] == incarnation["domain_incarnations"][channel["destination_domain"]]
    for index, channel in enumerate(channels):
        wire = next(row for row in transport["channels"] if row["index"] == channel["index"])
        expected = [{field: incarnation["endpoint_bindings"][index][field] for field in fields}
                    for incarnation in actual["incarnations"]]
        assert wire["bindings"] == expected
        assert wire["stale_data_dropped"] and wire["stale_credit_dropped"]
        assert all(wire[field] > 0 for field in ("tx", "ack", "delivered", "returned"))
        assert all(expected[1][field] > expected[0][field] for field in fields[1:])
    assert transport["clock_periods"] == [6, 10] and transport["clock_phases"] == [0, 1]
    tick = transport["cycles"]
    assert transport["local_cycles"] == [tick // 6 + 1, (tick - 1) // 10 + 1]
    assert len(transport["links"]) == 2
    for role, link in enumerate(transport["links"]):
        assert link["source"] == role and link["destination"] == 1 - role and link["capacity"] == 1
        assert link["injected"] == 8 and link["source_stalls"] > 0 and link["delivered"] > 0
        assert link["remaining"] in (0, 1) and link["accepted"] == link["delivered"] + link["remaining"]


def main() -> None:
    """Consume an existing source build; failed attempts remain in their fresh stage directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, type=lambda text: Path(text).resolve())
    parser.add_argument("--bundle", type=lambda text: Path(text).resolve())
    parser.add_argument("--compiled", type=lambda text: Path(text).resolve())
    parser.add_argument("--network", type=lambda text: Path(text).resolve(), help="independent network source bundle")
    parser.add_argument("--network-compiled", type=lambda text: Path(text).resolve())
    parser.add_argument("--endpoint-bundle", type=lambda text: Path(text).resolve(), help="retained native endpoint source bundle")
    parser.add_argument("--endpoint-compiled", type=lambda text: Path(text).resolve())
    parser.add_argument("--network-record", type=lambda text: Path(text).resolve(), help="emission dependency record; default network parent/emission.json")
    parser.add_argument("--namespace", type=int, default=1, help="nonzero endpoint namespace for this fresh cold-reset simulator")
    parser.add_argument("--binary", type=lambda text: Path(text).resolve())
    parser.add_argument("--native", type=lambda text: Path(text).resolve())
    parser.add_argument("--compare-result", type=lambda text: Path(text).resolve())
    parser.add_argument("--profile", default="test")
    parser.add_argument("--ebin", action="append", default=[], type=lambda text: Path(text).resolve())
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    if not args.binary and not args.bundle:
        parser.error("supply --bundle or a verified --binary")
    if not args.build_only and not args.native:
        parser.error("a witness requires the retained --native oracle.json")
    if not 0 < args.namespace < 1 << 64:
        parser.error("--namespace must be a nonzero unsigned 64-bit value")
    if args.binary and any((args.bundle, args.compiled, args.network, args.network_compiled,
                            args.endpoint_bundle, args.endpoint_compiled, args.network_record)):
        parser.error("--binary already binds its exact source and compiled RTL")
    if args.network and not args.endpoint_bundle:
        parser.error("--network requires its retained --endpoint-bundle")
    if not args.network and any((args.network_compiled, args.endpoint_bundle, args.endpoint_compiled, args.network_record)):
        parser.error("endpoint and network dependency options require --network")
    args.stage.mkdir()
    if args.binary:
        binary, bundle = reuse(args.binary)
        network_name = json.loads(binary.with_suffix(".json").read_text()).get("network")
        network = Path(network_name) if network_name else None
    else:
        bundle = args.bundle
        compiled = args.compiled or (bundle / "compiled").resolve()
        network = args.network
        if network:
            binary = compile_network_adapter(bundle, compiled, network,
                args.network_compiled or (network / "compiled").resolve(), args.endpoint_bundle,
                args.endpoint_compiled or (args.endpoint_bundle / "compiled").resolve(),
                args.network_record or network.parent / "emission.json", args.stage, args.profile, args.ebin)
        else:
            binary = compile_adapter(bundle, compiled, args.stage)
    if not args.build_only:
        witness(binary, bundle, args.native, args.stage, args.profile, args.ebin, args.compare_result, network, args.namespace)


if __name__ == "__main__":
    main()
