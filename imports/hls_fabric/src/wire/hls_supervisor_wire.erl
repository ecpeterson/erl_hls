-module(hls_supervisor_wire).
-moduledoc "Retained wire contract for a compiled supervisor's parent lifecycle, delegated identity grant and bounded child admission. hls_supervisor_fabric uses this management-only channel; child application streams retain their own domain codecs and retirement frontiers.".
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Trusted emitted interface and canonical management packets.
-export([load/1, command/4, observation/2]).
-export_type([interface/0, command/0, observation/0]).

-doc "Trusted source-generated parent management interface; enum providers must remain available at runtime.".
-type interface() :: #{
    kind := supervisor_management,
    management_route := hls_fabric:route(),
    codecs := #{atom() := hls_type:descriptor()},
    slots := #{atom() := hls_nums:u32()}
}.
-doc "Parent inspection/lifecycle/grant, or an exact-parent-incarnation operation on one compiled child slot.".
-type command() ::
    none
    | hls_domain_lifecycle:input()
    | {grant, hls_domain:incarnation(), hls_domain:incarnation(), hls_domain:incarnation()}
    | {child, start | stop | inspect, hls_domain:incarnation(), hls_nums:u32(), hls_nums:u64()}.
-doc "One complete correlated device observation, including the actual grant acknowledgement and current local supervisor outcome.".
-type observation() :: #{
    session := hls_nums:u64(),
    sequence := hls_nums:u32(),
    output := hls_domain_lifecycle:output(),
    grant_accepted := boolean(),
    supervisor_phase := atom(),
    supervisor_reason := atom(),
    grant_next := hls_nums:u64(),
    child_status := hls_supervisor_lifecycle:status(),
    child_slot := hls_nums:u32(),
    child_phase := hls_supervisor_lifecycle:child_phase(),
    child_incarnation := hls_nums:u64()
}.

-doc "Validates an emitted parent interface or its enclosing supervisor bundle. Paths are trusted local build products, never network terms.".
-spec load(interface() | map() | file:filename()) -> interface().
load(#{parent_stream := #{interface := Parent}}) ->
    load(Parent);
load(
    #{
        kind := supervisor_management,
        management_route := {Source, Destination},
        codecs := Codecs,
        slots := Slots
    } =
        I
) when
    is_integer(Source),
    Source >= 0,
    Source < (1 bsl 16),
    is_integer(Destination),
    Destination >= 0,
    Destination < (1 bsl 16)
->
    [
        hls_type:width(maps:get(K, Codecs))
     || K <- [
            operation,
            status,
            action,
            phase,
            fault,
            supervisor_phase,
            supervisor_reason,
            supervisor_status,
            child_phase
        ]
    ],
    true = lists:all(
        fun({Id, Slot}) ->
            is_atom(Id) andalso is_integer(Slot) andalso Slot >= 0 andalso Slot < (1 bsl 32)
        end,
        maps:to_list(Slots)
    ),
    true = map_size(Slots) =:= length(lists:usort(maps:values(Slots))),
    I;
load(Path) when is_list(Path); is_binary(Path) ->
    {ok, Bytes} = file:read_file(Path),
    load(binary_to_term(Bytes)).

-doc "Encodes a fresh nonwrapping correlation ID. A repeated grant carries the same epoch and interval; encoding never allocates an identity.".
-spec command(hls_nums:u64(), hls_nums:u32(), command(), interface()) ->
    {0 | 1 | 5 | 6 | 7 | 8, binary()}.
command(Session, Sequence, {grant, Epoch, First, Last}, _I) when
    Session > 0,
    Sequence > 0,
    Epoch > 0,
    First > 0,
    First =< Last,
    Last < ((1 bsl 64) - 1)
->
    {5,
        <<Session:64/little, Sequence:32/little, Epoch:64/little, First:64/little, Last:64/little>>};
command(Session, Sequence, {child, Op, Epoch, Slot, Expected}, _I) when
    Session > 0,
    Sequence > 0,
    Epoch > 0,
    Slot >= 0,
    Slot < (1 bsl 32),
    Expected >= 0,
    Expected < (1 bsl 64)
->
    Tag =
        case Op of
            start -> 6;
            stop -> 7;
            inspect -> 8
        end,
    {Tag,
        <<Session:64/little, Sequence:32/little, Epoch:64/little, Slot:32/little,
            Expected:64/little>>};
command(Session, Sequence, Input, #{codecs := Codecs}) when Sequence > 0 ->
    hls_domain_wire:management(Session, Sequence, Input, #{codecs => Codecs}).

-doc "Decodes the standard lifecycle prefix and supervisor suffix. Parent management has no application outputs, so source and frontier fields must be zero.".
-spec observation(binary(), interface()) -> observation().
observation(
    <<Prefix:72/binary, Accepted:32/little, Phase:32/little, Reason:32/little, Next:64/little,
        ChildStatus:32/little, Slot:32/little, ChildPhase:32/little, ChildIncarnation:64/little>>,
    #{
        codecs := Codecs
    }
) when Accepted =< 1 ->
    {Session, Sequence, Output, 0, 0, 0} = hls_domain_wire:observation(Prefix, #{codecs => Codecs}),
    #{
        session => Session,
        sequence => Sequence,
        output => Output,
        grant_accepted => Accepted =:= 1,
        supervisor_phase => value(supervisor_phase, Phase, Codecs),
        supervisor_reason => value(supervisor_reason, Reason, Codecs),
        grant_next => Next,
        child_status => value(supervisor_status, ChildStatus, Codecs),
        child_slot => Slot,
        child_phase => value(child_phase, ChildPhase, Codecs),
        child_incarnation => ChildIncarnation
    }.

%% Exact widths reject padding that would otherwise alias another enum member.
-spec value(atom(), non_neg_integer(), #{atom() => hls_type:descriptor()}) -> atom().
value(Name, Code, Codecs) ->
    Type = maps:get(Name, Codecs),
    Width = hls_type:width(Type),
    true = Code < (1 bsl Width),
    {Value, <<>>} = hls_type:unpack(<<Code:Width>>, Type),
    Value.
