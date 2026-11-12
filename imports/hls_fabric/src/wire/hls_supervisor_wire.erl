-module(hls_supervisor_wire).
-moduledoc "Retained wire contract for a compiled supervisor's parent lifecycle and delegated identity grant. hls_supervisor_fabric uses this management-only channel; child application streams retain their own domain codecs and retirement frontiers.".
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Trusted emitted interface and canonical management packets.
-export([load/1, command/4, observation/2]).
-export_type([interface/0, command/0, observation/0]).

-doc "Trusted source-generated parent management interface; enum providers must remain available at runtime.".
-type interface() :: #{
    kind := supervisor_management,
    management_route := hls_fabric:route(),
    codecs := #{atom() := hls_type:descriptor()}
}.
-doc "Inspect, an existing lifecycle command, or one already durably reserved incarnation interval.".
-type command() ::
    none
    | hls_domain_lifecycle:input()
    | {grant, hls_domain:incarnation(), hls_domain:incarnation(), hls_domain:incarnation()}.
-doc "One complete correlated device observation, including the actual grant acknowledgement and current local supervisor outcome.".
-type observation() :: #{
    session := hls_nums:u64(),
    sequence := hls_nums:u32(),
    output := hls_domain_lifecycle:output(),
    grant_accepted := boolean(),
    supervisor_phase := atom(),
    supervisor_reason := atom(),
    grant_next := hls_nums:u64()
}.

-doc "Validates an emitted parent interface or its enclosing supervisor bundle. Paths are trusted local build products, never network terms.".
-spec load(interface() | map() | file:filename()) -> interface().
load(#{parent_stream := #{interface := Parent}}) ->
    load(Parent);
load(
    #{kind := supervisor_management, management_route := {Source, Destination}, codecs := Codecs} =
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
            supervisor_reason
        ]
    ],
    I;
load(Path) when is_list(Path); is_binary(Path) ->
    {ok, Bytes} = file:read_file(Path),
    load(binary_to_term(Bytes)).

-doc "Encodes a fresh nonwrapping correlation ID. A repeated grant carries the same epoch and interval; encoding never allocates an identity.".
-spec command(hls_nums:u64(), hls_nums:u32(), command(), interface()) -> {0 | 1 | 5, binary()}.
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
command(Session, Sequence, Input, #{codecs := Codecs}) when Sequence > 0 ->
    hls_domain_wire:management(Session, Sequence, Input, #{codecs => Codecs}).

-doc "Decodes the standard lifecycle prefix and supervisor suffix. Parent management has no application outputs, so source and frontier fields must be zero.".
-spec observation(binary(), interface()) -> observation().
observation(
    <<Prefix:72/binary, Accepted:32/little, Phase:32/little, Reason:32/little, Next:64/little>>, #{
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
        grant_next => Next
    }.

%% Exact widths reject padding that would otherwise alias another enum member.
-spec value(atom(), non_neg_integer(), #{atom() => hls_type:descriptor()}) -> atom().
value(Name, Code, Codecs) ->
    Type = maps:get(Name, Codecs),
    Width = hls_type:width(Type),
    true = Code < (1 bsl Width),
    {Value, <<>>} = hls_type:unpack(<<Code:Width>>, Type),
    Value.
