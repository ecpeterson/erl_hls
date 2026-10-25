#!/usr/bin/env bash
set -euo pipefail
stage=${1:?usage: prepare_xls_sim.sh STAGE}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$stage"
stage=$(cd "$stage" && pwd)
cd "$project_root"
rebar3 as test compile
source tools/backend_env.sh test
# Source listings and common host transports retain one compiler-owned implementation.
bash "$erl_hls_root/tools/prepare_xls_sim.sh" "$stage"
ERL_HLS_STAGE="$stage" erl -noshell -eval '
    Stage = os:getenv("ERL_HLS_STAGE"),
        #{
            distance := DemoDistance,
            noise_rate := DemoNoiseRate
        } = phi_memory_demo:fixture(),
        PhiNoiseDistance = case os:getenv("ERL_HLS_PHI_DISTANCE") of
            false -> DemoDistance;
            DistanceText -> list_to_integer(DistanceText)
        end,
        PhiNoiseRate = case os:getenv("ERL_HLS_PHI_NOISE_RATE") of
            false -> DemoNoiseRate;
            RateText -> list_to_integer(RateText)
        end,
        SchedulerProfile = case os:getenv("ERL_HLS_PHI_SHARDS") of
            false -> 2;
            ShardText -> {phi_shards, list_to_integer(ShardText)}
        end,
        PhiNoisePlan = hls_topology:normalize(
            phi_noise_topology:topology(PhiNoiseDistance, PhiNoiseRate)
        ),
        PhiNoisePhysical = phi_shared_noise_topology_dslx:profile(
            SchedulerProfile
        ),
        %% The routine D1 closeout fixture disables random injection so empty
        %% decoder planes let the ERTS witness terminate deterministically.
        PhiNoiseSmokePlan = hls_topology:normalize(
            phi_noise_topology:topology(1, 0)
        ),
        PhiNoiseSmokePhysical = phi_shared_noise_topology_dslx:profile(),
        PhiNoiseSmokeScheduler = hls_scheduler_plan:normalize(
            PhiNoiseSmokePlan, maps:get(scheduler_groups, PhiNoiseSmokePhysical)
        ),
        %% Both schedulers in each family must agree with the fixture layout.
        [#{state_width := DataWidth}, #{state_width := DataWidth},
         #{state_width := PhiWidth}, #{state_width := PhiWidth},
         #{state_width := SyndromeWidth}, #{state_width := SyndromeWidth}] =
            xls_scheduler_ram_v:bindings(PhiNoiseSmokeScheduler),
        ok = file:write_file(filename:join(Stage,"phi_noise_topology_smoke_rams.vh"),
            ["// Generated from the D1 scheduler plan.\n",
             [io_lib:format("localparam integer ~s_STATE_WIDTH = ~B;~n", [Name, Width])
             || {Name, Width} <- [{"DATA", DataWidth}, {"PHI", PhiWidth},
                                 {"SYNDROME", SyndromeWidth}]]]),
        ProfileShardCount = case os:getenv("ERL_HLS_PHI_PROFILE_SHARDS") of
            false -> 3;
            ProfileShardText -> list_to_integer(ProfileShardText)
        end,
        ProfileEffectWindowPartition = case os:getenv(
            "ERL_HLS_PHI_PROFILE_EFFECT_WINDOWS"
        ) of
            false -> global;
            "global" -> global;
            "weak_components" -> weak_components;
            PartitionText -> error({effect_window_partition, PartitionText})
        end,
        ProfileDimension = fun(Name) ->
            case os:getenv(Name) of false -> 3; Text -> list_to_integer(Text) end
        end,
        ProfilePlanes = case os:getenv("ERL_HLS_PHI_PROFILE_PLANES") of
            false -> [x, z];
            "xz" -> [x, z];
            "x" -> [x];
            "z" -> [z];
            PlaneText -> error({invalid_profile_planes, PlaneText})
        end,
        ProfileConfig = phi_decoder_profile:normalize(#{
            shape => [ProfileDimension("ERL_HLS_PHI_PROFILE_WIDTH"),
                      ProfileDimension("ERL_HLS_PHI_PROFILE_HEIGHT")],
            planes => ProfilePlanes, shards => ProfileShardCount
        }),
        #{files := ProfileFiles, result := #{requirements := ProfileRequirements}} =
            phi_decoder_profile_build:emit(ProfileConfig,
                #{effect_window_partition => ProfileEffectWindowPartition}),
        ArtifactRequirementMaps = [
            ProfileRequirements,
            xls_shared_topology_dslx:artifact_requirements(
                PhiNoisePlan,
                PhiNoisePhysical
            ),
            xls_shared_topology_dslx:artifact_requirements(
                PhiNoiseSmokePlan,
                PhiNoiseSmokePhysical
            )
        ],
        SharedServiceFor = fun(Module) ->
            Modes = lists:usort([
                Mode
                || Requirements <- ArtifactRequirementMaps,
                   #{shared_service := Mode} <- [
                       maps:get(Module, Requirements, none)
                   ]
            ]),
            case Modes of
                [] -> ordinary;
                [Mode] -> Mode;
                _ -> error({mixed_staged_actor_artifacts, Module, Modes})
            end
        end,
        %% Shared staging must agree with the already prepared profile actors.
        [_ = SharedServiceFor(Module) || Module <- maps:keys(ProfileRequirements)],
        PhenomData = xls_shared_parse:to_xls(
            "src/examples/phi_decoder/phenom_data_cell.erl",
            #{shared_service => SharedServiceFor(phenom_data_cell)}
        ),
        PhenomSyndrome = xls_shared_parse:to_xls(
            "src/examples/phi_decoder/phenom_syndrome_cell.erl",
            #{shared_service => SharedServiceFor(phenom_syndrome_cell)}
        ),
        PhiNoiseTopology = xls_shared_topology_dslx:emit(
            PhiNoisePlan,
            PhiNoisePhysical
        ),
        PhiNoiseTopologySmoke = xls_shared_topology_dslx:emit(
            PhiNoiseSmokePlan,
            PhiNoiseSmokePhysical
        ),
        PhiBridgeDistance = case os:getenv(
            "ERL_HLS_PHI_BRIDGE_DISTANCE"
        ) of
            false -> 1;
            "demo" -> DemoDistance;
            Text -> list_to_integer(Text)
        end,
        GatewayProfile = case PhiBridgeDistance of
            3 -> SchedulerProfile;
            1 -> 2
        end,
        PhiMemoryGateway = case PhiBridgeDistance of
            3 -> phi_memory_gateway_dslx:to_dslx(3, GatewayProfile);
            1 -> phi_memory_gateway_dslx:to_dslx(1)
        end,
        PhiMemoryDebugTop = phi_memory_debug_top_v:to_verilog(
            GatewayProfile
        ),
        maps:foreach(fun(Name, Data) ->
            ok = file:write_file(filename:join(Stage, Name), Data)
        end, ProfileFiles),
        ok = file:write_file(filename:join(Stage, "phenom_data_cell.x"), PhenomData),
        ok = file:write_file(filename:join(Stage, "phenom_syndrome_cell.x"), PhenomSyndrome),
        ok = file:write_file(filename:join(Stage, "phi_noise_topology.x"), PhiNoiseTopology),
        ok = file:write_file(filename:join(Stage, "phi_noise_topology_smoke.x"), PhiNoiseTopologySmoke),
        ok = file:write_file(filename:join(Stage, "phi_memory_gateway.x"), PhiMemoryGateway),
        ok = file:write_file(filename:join(Stage, "phi_memory_debug_top.v"), PhiMemoryDebugTop),
        halt().'
cp priv/xls/lib/*.x "$stage/"
cp test/rtl/phi_noise_topology_smoke_tb.sv test/rtl/phi_noise_topology_tb.sv \
   test/rtl/phi_decoder_profile_tb.sv test/rtl/phi_memory_bridge_tb.sv "$stage/"
cp tools/phi_scheduler_rams.sh tools/compile_phi_decoder_profile.py \
   tools/compile_phi_decoder_profile.sh "$stage/"
erlc -P \
    -o "$stage/test_src" test/phi_memory_bridge_tests.erl
cp "$stage/test_src/phi_memory_bridge_tests.P" "$stage/test_src/phi_memory_bridge_tests.erl"

cp test/rtl/xls_scheduler_profile.h "$stage/xls_scheduler_profile.h"
python3 - "$stage/xls_sim_bridge.c" <<'PYVPI'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text('#define XLS_SIM_OBSERVER "xls_scheduler_profile.h"\n' + path.read_text())
PYVPI
