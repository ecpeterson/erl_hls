-module(hls_target_native).
-moduledoc """
Validates the optional native placement/timing attachment of a spacetime physical catalogue. Native timing is static evidence with explicit units and unavailable values; it does not add execution dependencies or establish sensitization. Called by hls_target_physical after primitive/net identity validation.
""".
%% Internal physical-catalogue extension boundary.
-export([validate/3]).
-export_type([native/0]).

%% Missing native values are absent evidence, never numerical zero.
-type measured() :: number() | null.
%% Native port identity remains separate from installed primitive cells.
-type native_port() :: #{net := binary(), port := binary(), direction := input | output | inout}.
%% Net delay objects retain native endpoint metadata in properties; these values use picoseconds.
-type delay() :: #{
    net := binary(),
    id := binary(),
    fast_min_ps := measured(),
    fast_max_ps := measured(),
    slow_min_ps := measured(),
    slow_max_ps := measured(),
    properties := #{binary() => binary()}
}.
%% A sampled static path's slack/requirement/data delay use nanoseconds, not execution-clock units.
-type path() :: #{
    id := binary(),
    delay_type := binary(),
    startpoint := binary(),
    endpoint := binary(),
    start_clock := binary(),
    end_clock := binary(),
    slack_ns := measured(),
    datapath_ns := measured(),
    requirement_ns := measured(),
    logic_levels := non_neg_integer() | null,
    properties := #{binary() => binary()},
    members := [#{kind := binary(), name := binary()}]
}.

-doc "Typed native export context: primitive ports, canonical aliases, all-net query dispositions, native delay objects and sampled static paths. Timings retain their declared ps/ns units and distinguish pure interconnect from delay including intra-site contributions; whole_rtl may be null when that identity was not supplied. Export counters bound the supplied tables, not the completeness of timing APIs.".
-type native() :: #{
    part := binary(),
    tool := binary(),
    whole_rtl := binary() | null,
    net_delay_basis := binary(),
    sampled_nets := [binary()],
    sdf := #{fast := hls_target_sdf:description(), slow := hls_target_sdf:description()},
    export_bytes := non_neg_integer(),
    export_records := non_neg_integer(),
    ports := [native_port()],
    aliases := [#{id := binary(), net := binary()}],
    net_annotations := [
        #{
            net := binary(),
            route_status := binary(),
            type := binary(),
            flat_pin_count := non_neg_integer(),
            timing_status := binary()
        }
    ],
    net_delays := [delay()],
    paths := [path()],
    issues := [#{stage := binary(), object := binary(), reason := binary()}]
}.

-doc "Checks native references, unique endpoints/aliases, every net's explicit timing disposition, finite numeric bounds and path membership. Does not assess authenticity or convert static paths into execution edges. Raises {spacetime, Reason}.".
-spec validate([map()], [map()], native()) -> ok.
validate(Cells, Nets, #{
    part := Part,
    tool := Tool,
    whole_rtl := Whole,
    net_delay_basis := DelayBasis,
    sampled_nets := Sample,
    sdf := Sdf,
    export_bytes := Bytes,
    export_records := Records,
    ports := Ports,
    aliases := Aliases,
    net_annotations := Annotations,
    net_delays := Delays,
    paths := Paths,
    issues := Issues
}) ->
    text(Part),
    text(Tool),
    sdf(Sdf),
    require(
        lists:member(DelayBasis, [<<"interconnect_only">>, <<"including_intrasite">>]),
        native_net_delay_basis
    ),
    case Whole of
        null -> ok;
        _ -> text(Whole)
    end,
    require(is_integer(Bytes) andalso Bytes >= 0 andalso Bytes =< 268435456, native_byte_count),
    require(
        is_integer(Records) andalso Records >= 0 andalso Records =< 2000000, native_record_count
    ),
    C = index(Cells, id),
    N = index(Nets, id),
    PinRows = lists:append([
        [
            #{
                id => maps:get(native, P, <<
                    (maps:get(cell, P))/binary, "/", (maps:get(pin, P))/binary
                >>),
                cell => maps:get(cell, P),
                pin => maps:get(pin, P)
            }
         || P <- maps:get(pins, Net)
        ]
     || Net <- Nets
    ]),
    %% A leaf pin belongs to one canonical net; duplicated native pin identities reject.
    Pins = index(PinRows, id),
    PortIndex = index(Ports, port),
    lists:foreach(
        fun(#{net := Net, port := Port, direction := Direction}) ->
            reference(Net, N, port_net),
            text(Port),
            require(lists:member(Direction, [input, output, inout]), native_port_direction)
        end,
        Ports
    ),
    AliasIndex = index(Aliases, id),
    lists:foreach(
        fun(#{id := Id, net := Net}) ->
            text(Id),
            reference(Net, N, alias_net)
        end,
        Aliases
    ),
    A = index(Annotations, net),
    require(lists:sort(maps:keys(A)) =:= lists:sort(maps:keys(N)), native_net_coverage),
    lists:foreach(fun annotation/1, Annotations),
    Queried = [
        begin
            reference(Id, AliasIndex, sampled_net),
            maps:get(net, maps:get(Id, AliasIndex))
        end
     || Id <- Sample
    ],
    require(length(Queried) =:= length(lists:usort(Queried)), duplicate_sampled_net),
    require(
        lists:sort(Queried) =:=
            lists:sort([
                Net
             || #{net := Net, timing_status := Status} <- Annotations,
                Status =/= <<"not_queried">>
            ]),
        native_sample_coverage
    ),
    DelayIds = [{maps:get(net, D), maps:get(id, D)} || D <- Delays],
    require(length(DelayIds) =:= length(lists:usort(DelayIds)), duplicate_native_delay),
    lists:foreach(fun(D) -> delay(D, N) end, Delays),
    DelayCounts = lists:foldl(
        fun(#{net := Net}, Acc) -> maps:update_with(Net, fun(V) -> V + 1 end, 1, Acc) end,
        #{},
        Delays
    ),
    lists:foreach(
        fun(#{net := Net, timing_status := Status}) ->
            require(
                (Status =:= <<"available">>) =:= (maps:get(Net, DelayCounts, 0) > 0),
                {native_timing_coverage, Net}
            )
        end,
        Annotations
    ),
    _ = index(Paths, id),
    Context = #{cell => C, net => N, pin => Pins, port => PortIndex},
    lists:foreach(fun(P) -> path(P, Context) end, Paths),
    lists:foreach(
        fun(#{stage := Stage, object := Object, reason := Reason}) ->
            text(Stage),
            string(Object),
            text(Reason)
        end,
        Issues
    ),
    ok;
validate(_, _, _) ->
    fail(invalid_native_attachment).

%% Corner provenance is explicit and both files must describe the same instance population.
-spec sdf(#{fast := hls_target_sdf:description(), slow := hls_target_sdf:description()}) ->
    ok.
sdf(Sdf) ->
    require(lists:sort(maps:keys(Sdf)) =:= [fast, slow], native_sdf_corners),
    Populations = [
        begin
            Description = maps:get(Corner, Sdf),
            ok = hls_target_sdf:validate_description(Description),
            #{
                source := #{corner := DeclaredCorner, mode := Mode},
                instance_population_sha256 := PopulationHash,
                file := File
            } = Description,
            require(DeclaredCorner =:= Corner andalso Mode =:= sta, native_sdf_provenance),
            require(
                File =:= <<"timing-", (atom_to_binary(Corner))/binary, ".sdf">>, native_sdf_file
            ),
            PopulationHash
        end
     || Corner <- [fast, slow]
    ],
    [Fast, Slow] = Populations,
    require(Fast =:= Slow, native_sdf_populations),
    ok.

%% A query disposition states whether zero returned delay objects means unsupported/missing evidence.
-spec annotation(map()) -> ok.
annotation(#{route_status := Route, type := Type, flat_pin_count := Count, timing_status := Status}) ->
    string(Route),
    string(Type),
    require(
        lists:member(Status, [<<"available">>, <<"empty">>, <<"error">>, <<"not_queried">>]),
        native_timing_status
    ),
    require(is_integer(Count) andalso Count >= 0 andalso Count < (1 bsl 53), native_pin_count).

%% Delay endpoints may be absent from Vivado's object; properties preserve that fact without guessing.
-spec delay(delay(), map()) -> ok.
delay(
    #{
        net := Net,
        id := Id,
        fast_min_ps := FMin,
        fast_max_ps := FMax,
        slow_min_ps := SMin,
        slow_max_ps := SMax,
        properties := Properties
    },
    Nets
) ->
    reference(Net, Nets, delay_net),
    text(Id),
    lists:foreach(fun(V) -> measured(V, 0) end, [FMin, FMax, SMin, SMax]),
    ordered(FMin, FMax),
    ordered(SMin, SMax),
    properties(Properties).

%% Known min/max corners must agree; an unavailable corner does not become a bound.
-spec ordered(measured(), measured()) -> ok.
ordered(null, _) -> ok;
ordered(_, null) -> ok;
ordered(A, B) -> require(A =< B, inverted_native_delay).

%% Native static-path membership can refer only to supplied primitive/net/endpoint objects.
-spec path(path(), map()) -> ok.
path(
    #{
        id := Id,
        delay_type := Type,
        startpoint := Start,
        endpoint := End,
        start_clock := SC,
        end_clock := EC,
        slack_ns := Slack,
        datapath_ns := Data,
        requirement_ns := Requirement,
        logic_levels := Levels,
        properties := Properties,
        members := Members
    },
    Context
) ->
    text(Id),
    require(lists:member(Type, [<<"max">>, <<"min">>]), native_delay_type),
    endpoint(Start, Context),
    endpoint(End, Context),
    string(SC),
    string(EC),
    measured(Slack, -1000000000000),
    measured(Data, 0),
    measured(Requirement, -1000000000000),
    require(
        Levels =:= null orelse (is_integer(Levels) andalso Levels >= 0 andalso Levels < 1000000),
        native_logic_levels
    ),
    properties(Properties),
    require(is_list(Members), native_path_members),
    lists:foreach(fun(M) -> member(M, Context) end, Members).

%% A timing endpoint must identify an exported leaf pin or a top-level port.
-spec endpoint(binary(), map()) -> ok.
endpoint(Name, #{pin := Pins, port := Ports}) ->
    text(Name),
    require(
        maps:is_key(Name, Pins) orelse maps:is_key(Name, Ports), {unknown_native_endpoint, Name}
    ).

%% Exporter kinds are fixed vocabulary; no external string is interned as an atom.
-spec member(map(), map()) -> ok.
member(#{kind := Kind, name := Name}, Context) ->
    Key =
        case Kind of
            <<"cell">> -> cell;
            <<"net">> -> net;
            <<"pin">> -> pin;
            <<"port">> -> port;
            _ -> fail({native_member_kind, Kind})
        end,
    reference(Name, maps:get(Key, Context), {path_member, Key}).

%% Large/nonfinite values cannot be mistaken for sensible placed timing measurements.
-spec measured(measured(), number()) -> ok.
measured(null, _) ->
    ok;
measured(N, Minimum) ->
    require(is_number(N) andalso N >= Minimum andalso N =< 1000000000000, native_timing_value).

%% Native properties may be blank strings but must retain valid text values.
-spec properties(map()) -> ok.
properties(Properties) ->
    require(is_map(Properties), native_properties),
    maps:foreach(
        fun(K, V) ->
            text(K),
            string(V)
        end,
        Properties
    ).

%% Duplicate IDs are rejected before constructing reference indexes.
-spec index([map()], atom()) -> map().
index(Rows, Key) ->
    require(is_list(Rows), native_rows),
    lists:foldl(
        fun(Row, A) ->
            Id = maps:get(Key, Row),
            text(Id),
            require(not maps:is_key(Id, A), {duplicate_native_id, Key, Id}),
            A#{Id => Row}
        end,
        #{},
        Rows
    ).

%% Reference checks never substitute guessed endpoints when extraction missed an object.
-spec reference(binary(), map(), term()) -> ok.
reference(Id, Table, Kind) ->
    text(Id),
    require(maps:is_key(Id, Table), {unknown_native_reference, Kind, Id}).

%% IDs and evidence labels are nonempty UTF-8 text.
-spec text(binary()) -> ok.
text(B) ->
    string(B),
    require(byte_size(B) > 0, native_empty_text).

%% Empty clocks/properties mean unavailable native metadata, not an invented default.
-spec string(binary()) -> ok.
string(B) -> require(is_binary(B) andalso unicode:characters_to_binary(B) =:= B, native_text).

%% Reuse the physical companion's contract error namespace.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> fail(Reason).

%% Native evidence failures block the combined catalogue rather than pruning bad rows.
-spec fail(term()) -> no_return().
fail(Reason) -> error({spacetime, Reason}).
