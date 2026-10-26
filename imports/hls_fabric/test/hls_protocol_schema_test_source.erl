-module(hls_protocol_schema_test_source).
-moduledoc "Compiles small source actors for protocol schema tests without supplying compiler artifacts by hand.".
-export([compile/1, compile/2]).

%% Record names and ordered fields use ordinary Erlang type syntax.
-type schema() :: {atom(), [{atom(), string()}]}.

-doc "Compiles a complete idle receiver for the supplied nonempty record declarations. Removes its temporary source before returning the fresh local-actor artifact, so consumers must use the retained compiler snapshot.".
-spec compile([schema(), ...]) -> hls_local_actor:artifact().
compile(Schemas) -> compile(Schemas, hls_frame_layout:default()).

-doc "Compiles the same ordinary receiver using an explicit canonical frame layout; oversized schemas reject before a rendered artifact is returned.".
-spec compile([schema(), ...], hls_frame_layout:layout()) -> hls_local_actor:artifact().
compile(Schemas, FrameLayout) ->
    Root = filename:join("_build", "protocol-schema-" ++
        integer_to_list(erlang:unique_integer([positive]))),
    File = filename:join(Root, "actor.erl"),
    ok = filelib:ensure_dir(File),
    try
        ok = file:write_file(File, source(Schemas)),
        hls_local_actor:render(hls_local_actor:prepare(File, [], FrameLayout))
    after
        file:delete(File), file:del_dir(Root)
    end.

%% Only schema declarations vary; every declared tag has an ordinary consuming callback.
-spec source([schema(), ...]) -> iodata().
source(Schemas) ->
    ["-module(hls_protocol_schema_test_actor).\n",
        "-behaviour(hls_statem).\n-compile({parse_transform, hls_pack}).\n",
        "-export([init/1, idle/3]).\n-hls_data(cell).\n-hls_phases([idle]).\n",
        "-hls_outputs([output]).\n-hls_mailbox_capacity(1).\n",
        io_lib:format("-hls_tags(~p).~n", [[Name || {Name, _} <- Schemas]]),
        "-record(cell, {value = hls_type:zero() :: hls_nums:u8()}).\n",
        [record(Name, Fields) || {Name, Fields} <- Schemas],
        "init([]) -> {ok, idle, #cell{}}.\n",
        "idle(enter, _, Cell) -> {Cell, []};\n",
        lists:join(";\n", [io_lib:format(
            "idle(cast, #~p{}, Cell) -> {idle, Cell, consume}", [Name])
            || {Name, _} <- Schemas]), ".\n"].

%% Default values use the actual provider's zero representation, including empty records.
-spec record(atom(), [{atom(), string()}]) -> iodata().
record(Name, Fields) ->
    [io_lib:format("-record(~p, {", [Name]),
        lists:join(", ", [io_lib:format("~p = hls_type:zero() :: ~s", [Field, Type])
            || {Field, Type} <- Fields]), "}).\n"].
