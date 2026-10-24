-module(hls_ci_snowflake).
-moduledoc "Small surface-window witness for the source protocol backend; no physical or QEC admission.".
-export([config/0, topology/0, emit/1, oracle/1]).

-doc "Selects the ordinary D2/H2 sources with a twelve-member flat barrier and bounded coordinator mailbox.".
-spec config() -> map().
config() ->
    Actors = "experiments/snowflake/actors/",
    #{sources => [{"experiments/snowflake/erlang/snowflake_geometry.erl", []},
        {Actors ++ "snowflake_actor_topology.erl", []},
        {Actors ++ "snowflake_vertex.erl", []},
        {Actors ++ "snowflake_coordinator.erl", [{d, 'SNOWFLAKE_COORDINATOR_SOURCES', 12},
            {d, 'SNOWFLAKE_COORDINATOR_MAILBOX', 16}]},
        {"test/hls_ci_snowflake.erl", []}],
      topology => {?MODULE, topology, []}, actor_limit => 13, activation => explicit_start}.

-doc "Uses the ordinary graph with independently accepted command copies. Each vertex receives an ordered slot from the same coordinator; its acknowledgment closes the barrier before the next command. This chooses buffered delivery explicitly instead of the scheduler's queued broadcast.".
-spec topology() -> hls_topology:spec().
topology() ->
    Topology = #{routes := [{{coordinator, command}, queued, Recipients} | Rest]} =
        snowflake_actor_topology:topology(2, 2),
    Topology#{routes := [{{coordinator, command}, buffered, Recipients} | Rest]}.

-doc "Emits one fresh complete source-protocol boundary using production compilation and topology checks.".
-spec emit(file:filename()) -> ok.
emit(Output) ->
    _ = hls_source_build:emit(boundary, config(), Output), ok.

-doc "Runs ordinary BEAM actors on eight finite syndrome sheets and writes independently calculated public frames. The reference checks each round's complete state and retirement; this is a finite witness, not decoder validation.".
-spec oracle(file:filename()) -> ok.
oracle(Output) ->
    Files = ["experiments/snowflake/erlang/snowflake_node.erl",
        "experiments/snowflake/erlang/snowflake_window.erl",
        "experiments/snowflake/actors/snowflake_actor_run.erl"],
    %% Use the same ordinary actors/options as emission, independent of generated hardware.
    lists:foreach(fun({File, Options}) ->
        {ok, Module, Bytes} = compile:file(File, [binary, debug_info, warnings_as_errors, report | Options]),
        {module, Module} = code:load_binary(Module, File, Bytes)
    end, maps:get(sources, config()) ++ [{File, []} || File <- Files]),
    Masks = [1, 2, 3, 0, 1, 0, 0, 0],
    Reports = snowflake_actor_run:run(2, 2, Masks),
    8 = length(Reports),
    Model = Output ++ ".model",
    ok = snowflake_actor_run:write_vectors(2, 2, Masks, Model),
    {ok, Bytes} = file:read_file(Model),
    Vectors = #{<<"sheets">> := Rows} = json:decode(Bytes),
    Canonical = [begin
        #{<<"sheet">> := Sheet, <<"input_mask">> := Mask, <<"corrections">> := Corrections} = Row,
        #{actor_round := Epoch} = Report,
        Row#{<<"input_frame">> := frame(snowflake_coordinator, {sf_input, Sheet, Mask}),
            <<"round_frame">> := frame(snowflake_coordinator, {sf_round, Sheet, Epoch}),
            <<"corrections">> := [C#{<<"frame">> := frame(snowflake_vertex,
                {sf_correction, maps:get(<<"sheet">>, C), maps:get(<<"source">>, C), maps:get(<<"edges">>, C)})}
                || C <- Corrections]}
    end || {Row, Report} <- lists:zip(Rows, Reports)],
    file:write_file(Output, json:encode(Vectors#{<<"sheets">> := Canonical}), [exclusive]).

%% Use ordinary BEAM packing for the protocol boundary's little-endian frame words.
%% The older experiment's vector file uses an MSB-header layout; its values, not
%% that incidental serialization, define this independent reference.
-spec frame(module(), tuple()) -> binary().
frame(Module, Message) ->
    Stream = Module:pack(Message), N = bit_size(Stream),
    true = N =< 96,
    <<Payload:96/little>> = <<Stream/bitstring, 0:(96-N)>>,
    Tag = Module:pack_tag(element(1, Message)),
    iolist_to_binary(io_lib:format("~32.16.0b", [(Payload bsl 32) bor (Tag bsl 24) bor ((N+31) div 32)])).
