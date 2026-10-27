-module(xls_regression_fixtures).
-moduledoc "Fixture orchestration shared by external compiler regression cases; expected values stay with their Erlang generators.".
-export([write/2, write/3]).
-export_type([suite/0]).

-doc "Named composite fixture suites; individual generators retain their existing write/1 APIs.".
-type suite() :: binary | direct_admission | entry_outcomes | names | reduction_dslx |
    logical_types | application_frames | deferred_replies | service_contracts.

-doc "Writes one suite's DSLX, testbench and oracle inputs into an existing stage directory. Source paths are relative to the compiler checkout; source and generation errors propagate.".
-spec write(suite(), file:filename()) -> ok.
%% Binary lowering and a real packed-sample actor share the observation harness.
write(binary, Stage) ->
    ok = xls_binary_dslx:write(Stage),
    actor(Stage, "packed_samples.x", "src/examples/packed_samples/packed_samples.erl");
%% Admission varies channel depth independently from the actor and mailbox-capacity fixtures.
write(direct_admission, Stage) ->
    ok = xls_large_mailbox_dslx:write(Stage),
    ok = actor(Stage, "ordered_egress_actor.x", "test/ordered_egress_actor.erl"),
    lists:foreach(fun(Depth) ->
        Path = filename:join([Stage, "d" ++ integer_to_list(Depth), "ordered_egress_topology.x"]),
        ok = filelib:ensure_dir(Path),
        Profile = (ordered_egress_topology:profile())#{channel_depth := Depth},
        ok = file:write_file(Path, xls_topology_dslx:emit(
            hls_topology:from_module(ordered_egress_topology), Profile))
    end, [1, 2]);
%% Entry branching, storage and known-bit witnesses use the same staged support files.
write(entry_outcomes, Stage) ->
    ok = xls_entry_outcome_dslx:write(Stage),
    ok = xls_entry_branch_dslx:write(Stage),
    ok = xls_entry_storage_dslx:write(Stage),
    xls_known_bits_dslx:write(Stage);
%% The unused-binding witness is checked with warnings promoted to errors.
write(names, Stage) ->
    ok = xls_names_dslx:write(Stage),
    ok = file:write_file(filename:join(Stage, "unused.x"), xls_short_circuit_dslx:to_dslx()),
    ok;
%% Signed-mask generation preserves the original source mutation and semantic snippets.
write(reduction_dslx, Stage) ->
    {ok, MaskSource} = file:read_file("test_data/hls_statem_mask_reduction_fixture.erl"),
    SignedSource = filename:join(Stage, "signed_mask.erl"),
    ok = file:write_file(SignedSource, binary:replace(MaskSource,
        <<"mask = hls_type:zero() :: hls_nums:u8()">>,
        <<"mask = hls_type:zero() :: hls_nums:s8()">>, [global])),
    lists:foreach(fun({Name, Source, Snippets}) ->
        X = xls_parse:to_xls(Source, #{direct_actor_debug => Name =:= "mask_debug"}),
        Tests = [begin {ok, B} = file:read_file("test_data/" ++ S ++ ".inc.x"), B end || S <- Snippets],
        ok = file:write_file(filename:join(Stage, Name ++ ".x"), [X, Tests])
    end, [{"reduction", "test_data/hls_statem_reduction_lower_fixture.erl", ["hls_statem_reduction_semantics"]},
          {"mask", "test_data/hls_statem_mask_reduction_fixture.erl", ["hls_statem_mask_reduction_semantics"]},
          {"mask_debug", "test_data/hls_statem_mask_reduction_fixture.erl", ["hls_statem_mask_debug_semantics"]},
          {"signed_mask", SignedSource, ["hls_statem_signed_mask_semantics"]},
          {"failure", "test/hls_reduction_failure_fixture.erl", ["hls_reduction_failure_semantics", "hls_reduction_failure_ordinary_semantics"]}]);
%% Logical codecs and both topology layouts share their BEAM vector corpus.
write(logical_types, Stage) ->
    ok = hls_logical_dslx:write(Stage),
    ok = hls_dense_topology_dslx:write(Stage),
    xls_struct_codec_dslx:write(Stage);
%% The ordinary frame service complements the handwritten frame-family DSLX witnesses.
write(application_frames, Stage) ->
    actor(Stage, "application_service.x", "test/xls_init_gs_fixture.erl");
%% Retained calls and their iterative drains use the existing singleton actor source.
write(deferred_replies, Stage) ->
    actor(Stage, "batch.x", "test/hls_deferred_fixture.erl");
%% Reply framing is generated from the same actor used by host contract tests.
write(service_contracts, Stage) ->
    actor(Stage, "service.x", "test/hls_reply_fixture.erl").

-doc "Writes one supported mixed-topology placement into its own existing stage directory. The source generator owns placement semantics and expected observations.".
-spec write(mixed_topology, file:filename(), direct | ingress_direct) -> ok.
write(mixed_topology, Stage, direct) -> hls_mixed_topology_dslx:write(direct, Stage);
write(mixed_topology, Stage, ingress_direct) -> hls_mixed_topology_dslx:write({ingress, direct}, Stage).

%% Actor lowering remains in the compiler; Python supplies only the stage directory.
-spec actor(file:filename(), string(), file:filename()) -> ok.
actor(Stage, Name, Source) ->
    ok = file:write_file(filename:join(Stage, Name), xls_parse:to_xls(Source)),
    ok.
