"""Emit Erlang-owned channel build policy and read retained policy without a checkout."""
from pathlib import Path
import json
import subprocess


def read(path: Path) -> dict:
    """Read a trusted versioned experiment profile without deriving its codegen policy.

    External adapters validate input hashes separately. These checks establish
    the record shape they consume; only Erlang renders scheduling flags.
    """
    value = json.loads(Path(path).read_text())
    if not isinstance(value, dict) or type(value.get("version")) is not int or value["version"] != 1:
        raise ValueError("unsupported backend build profile version")
    profile = value.get("profile")
    if not isinstance(profile, dict) or profile.get("backend") != "channel_scheduler" or profile.get("placement") != "prepared_source":
        raise ValueError("backend build profile must describe prepared channel source")
    schedules = profile.get("schedules")
    schedule = schedules.get("channel") if isinstance(schedules, dict) else None
    if not isinstance(schedule, dict):
        raise ValueError("backend build profile omits its channel schedule")
    for field in ("pipeline_stages", "executor_result_delay"):
        if type(schedule.get(field)) is not int:
            raise ValueError(f"backend build profile has invalid {field}")
    interval = schedule.get("initiation_interval")
    if type(interval) is not int and interval != "tool_default":
        raise ValueError("backend build profile has invalid initiation_interval")
    if not isinstance(schedule.get("delay_model"), str) or not schedule["delay_model"]:
        raise ValueError("backend build profile omits its delay model")
    if any(type(schedule.get(field)) is not bool for field in ("flop_inputs", "flop_outputs")):
        raise ValueError("backend build profile omits its register policy")
    if schedule.get("fifo_module") not in ("default", "none"):
        raise ValueError("backend build profile omits its FIFO policy")
    postprocess = profile.get("postprocess")
    if not isinstance(postprocess, dict) or postprocess.get("completion_storage") not in ("registers", "lutram"):
        raise ValueError("backend build profile has invalid completion storage")
    frame = profile.get("frame_abi")
    if not isinstance(frame, dict) or not isinstance(frame.get("name"), str) or any(
            type(frame.get(field)) is not int for field in ("header_bits", "payload_bits", "frame_bits", "payload_words")):
        raise ValueError("backend build profile omits its frame ABI")
    if type(frame.get("parameterized")) is not bool or profile.get("tools") != {
            "provider": "xls", "identity": "external_compilation"}:
        raise ValueError("backend build profile has invalid frame/tool identity shape")
    flags = value.get("codegen_flags")
    if not isinstance(flags, list) or not flags or any(
            not isinstance(flag, str) or not flag.startswith("--") or any(c in flag for c in "\r\n\0")
            for flag in flags):
        raise ValueError("backend build profile omits codegen arguments")
    return value


def emit(output: Path, *, profile: str = "default", public: Path | None = None,
         stages: int = 2, initiation_interval: int | None = 1, delay_model: str = "unit",
         executor_result_delay: int = 0, completion_storage: str = "registers") -> dict:
    """Write one fresh policy file using the selected fabric/compiler BEAM profile.

    None requests XLS's unspecified initiation interval; ordinary builds default
    to one. No source or XLS tool is read. Imports used only for emission remain
    lazy so detached stages can retain this file solely as a standard-library reader.
    """
    from backend_paths import erlang_environment

    output = Path(output).absolute()
    command = ["erl", "+S", "2:2", "-noshell", "-s", "hls_fabric_cli", "main", "-extra", "profile",
               "--output", str(output), "--pipeline-stages", str(stages),
               "--initiation-interval", "tool_default" if initiation_interval is None else str(initiation_interval),
               "--delay-model", delay_model, "--executor-result-delay", str(executor_result_delay),
               "--completion-storage", completion_storage]
    result = subprocess.run(command, env=erlang_environment(profile, compiler=public),
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError("backend build profile emission failed: " + result.stderr.strip())
    return read(output)
