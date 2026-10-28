-module(hls_ci_snowflake).
-moduledoc "Small surface-window witness for the source protocol backend; no physical or QEC admission.".
-export([config/0, topology/0, write/1, oracle/1]).

-doc "Selects the ordinary D2/H2 sources with a twelve-member flat barrier and bounded coordinator mailbox.".
-spec config() -> map().
config() ->
    snowflake_source:config().

-doc "Uses the ordinary graph with independently accepted command copies. Each vertex receives an ordered slot from the same coordinator; its acknowledgment closes the barrier before the next command. This chooses buffered delivery explicitly instead of the scheduler's queued broadcast.".
-spec topology() -> hls_topology:spec().
topology() ->
    snowflake_source:topology().

-doc "Writes one fresh complete source-protocol boundary using production compilation and topology checks.".
-spec write(file:filename()) -> ok.
write(Output) ->
    _ = hls_source_build:write(boundary, config(), Output), ok.

-doc "Runs ordinary BEAM actors on eight finite syndrome sheets and writes independently calculated public frames. The reference checks each round's complete state and retirement; this is a finite witness, not decoder validation.".
-spec oracle(file:filename()) -> ok.
oracle(Output) ->
    Root = code:lib_dir(hls_snowflake),
    Files = [filename:join([Root, "src", Name ++ ".erl"]) || Name <-
        ["snowflake_node", "snowflake_window", "snowflake_actor_run"]],
    Includes = [{i, filename:join(Root, "include")}],
    %% Use the same ordinary actors/options as emission, independent of generated hardware.
    lists:foreach(fun({File, Options}) ->
        {ok, Module, Bytes} = compile:file(File, [binary, debug_info, warnings_as_errors, report | Options]),
        {module, Module} = code:load_binary(Module, File, Bytes)
    end, maps:get(sources, config()) ++ [{File, Includes} || File <- Files]),
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
