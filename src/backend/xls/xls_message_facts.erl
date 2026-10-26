-module(xls_message_facts).
-moduledoc "Conservative outgoing-message facts from the ordinary entry encoder. Facts condition on an emitted message; they do not establish reachability, delivery, receiver acceptance or permission to erase evaluated expressions. No rendering is changed.".
-export([from_file/2, from_file/3, validate/3, manifest/1, on_ports/2, frame_bits/2, frame_cases/2]).
-export_type([facts/0, domain/0]).

-doc "ABI-stream field bounds: a finite value set, a fixed-bit mask/value pair, or unknown. Bounds overapproximate emitted values and do not imply reachability.".
-type domain() :: unknown | {values, [bitstring(), ...]} | {bits, bitstring(), bitstring()}.

-doc "Source-bound analysis of all ordinary entry alternatives. Saved values must be validated against current source before use.".
-opaque facts() :: #{version := 3, frame_layout := hls_frame_layout:layout(), tags := #{atom() => 0 .. ((1 bsl 8) - 1)}, identity := map(), outputs := [atom()],
    reply_port := none | {port, atom()}, alternatives := [map()]}.

-doc "Returns unchanged ordinary lowering and message facts from its exact entry-storage layouts. Options retain ordinary preprocessing semantics; invalid actors fail ordinary lowering.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context()) ->
    {xls_actor_codegen:spec(), facts()}.
from_file(Filename, Options) -> from_file(Filename, Options, hls_frame_layout:default()).

-doc "Derives source-bound message facts and ordinary lowering under the same explicit frame layout.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context(),
    hls_frame_layout:layout()) -> {xls_actor_codegen:spec(), facts()}.
from_file(Filename, Options, FrameLayout) ->
    {Spec, Plan} = xls_statem_plan:from_file(Filename, Options, FrameLayout),
    Identity = maps:with([source, source_sha256, artifact_sha256, planner_md5],
        xls_statem_plan:manifest(Plan)),
    #{entries := Entries, output_names := Outputs, retained_calls := Calls} = Spec,
    ReplyPort = case Calls of none -> none; #{port := Port} -> {port, Port} end,
    Alternatives = [#{phase => Phase, layout => Layout, order => Order,
        port => Port, tag => Tag, fields => [field(F) || F <- Fields]}
        || #{layouts := Layouts} <- Entries,
            #{phase := Phase, layout := Layout, storage := #{effects := Effects}} <- Layouts,
            {Order, #{port := Port, tag := Tag, fields := Fields}} <- lists:enumerate(0, Effects)],
    {Spec, #{version => 3, frame_layout => FrameLayout, tags => maps:from_list([{T, I} || {I, T} <- lists:enumerate(3, maps:get(message_names, Spec))]), identity => Identity#{analyzer_md5 =>
        binary:encode_hex(?MODULE:module_info(md5), lowercase)}, outputs => Outputs,
        reply_port => ReplyPort, alternatives => Alternatives}}.

-doc "Recompiles source and compares the complete analysis, including all facts and identities. Rejects edited or stale facts; this is freshness checking, not an equivalence proof.".
-spec validate(file:filename(), [hls_source:option()] | hls_source:context(), facts()) -> ok.
validate(Filename, Options, Facts = #{frame_layout := Layout}) ->
    {_, Current} = from_file(Filename, Options, Layout),
    case Current =:= Facts of true -> ok; false -> error(stale_message_facts) end.

-doc "Returns source/tool identities and analysis scope. This inventory is not a certificate of protocol safety or hardware savings.".
-spec manifest(facts()) -> map().
manifest(#{frame_layout := Layout, version := Version, identity := Identity, outputs := Outputs,
        alternatives := Alternatives, reply_port := Reply}) ->
    Identity#{frame_layout => hls_frame_layout:descriptor(Layout), version => Version, role => message_analysis_only, outputs => Outputs,
        entry_alternatives => length(Alternatives), reply_port => Reply}.

-doc "Joins all selected source ports, including aliases on one lane. Requires a nonempty set of declared ports and freshly derived or validated facts. Closed entry schemas bound emitted messages, not source evaluations or incoming traffic. Alternatives preserve phase/layout/order and field correlations; marginal domains lose correlations. A retained-reply port makes the full schema set unknown, including generated error replies. An empty closed set means no entry emission, never a proof of receiver acceptance.".
-spec on_ports(facts(), [atom(), ...]) -> map().
on_ports(#{outputs := Outputs, alternatives := Alternatives, reply_port := Reply}, Ports) ->
    ok = check_ports(Ports, Outputs),
    Selected = [A || A = #{port := Port} <- Alternatives, lists:member(Port, Ports)],
    Unknown = case Reply of {port, P} -> lists:member(P, Ports); none -> false end,
    Schemas = schemas(Selected),
    #{source_ports => lists:usort(Ports), closed => not Unknown,
        schemas => case Unknown of true -> unknown; false -> Schemas end,
        entry_schemas => Schemas, alternatives => Selected,
        unknown_sources => case Unknown of true -> [retained_reply]; false -> [] end}.

%% Never let a misspelled or empty port selection become a vacuous bound.
-spec check_ports([atom()], [atom()]) -> ok.
check_ports([], _Outputs) -> error(empty_message_ports);
check_ports(Ports, Outputs) ->
    case lists:usort(Ports) -- Outputs of
        [] -> ok;
        Missing -> error({unknown_message_ports, Missing})
    end.

%% Reuse the exact ABI constants which ordinary entry decoding reconstructs.
%% Partial integer facts are converted from numeric to physical ABI stream order.
-spec field(map()) -> map().
field(#{name := Name, type := Type, constant := Bits}) ->
    #{name => Name, type => Type, domain => {values, [Bits]}};
field(#{name := Name, type := Type, known := #{mask := Mask, value := Value}}) ->
    Unsigned = {hls_type, hls_nums, uN, [hls_type:width(Type)]},
    #{name => Name, type => Type,
        domain => {bits, hls_type:pack(Mask, Unsigned), hls_type:pack(Value, Unsigned)}};
field(#{name := Name, type := Type, offset := _Offset}) ->
    #{name => Name, type => Type, domain => unknown}.

%% Schema alternatives stay separate; field-wise joins are conservative and
%% must not be interpreted as establishing every Cartesian-product combination.
-spec schemas([map()]) -> [map()].
schemas(Alternatives) ->
    [#{tag => Tag, fields => join_fields([Fs || #{tag := T, fields := Fs} <- Alternatives,
        T =:= Tag])} || Tag <- lists:usort([T || #{tag := T} <- Alternatives])].

%% All occurrences of one source schema have the same checked field names/types.
-spec join_fields([[map()], ...]) -> [map()].
join_fields([Fields | Rest]) ->
    lists:foldl(fun(Other, Acc) -> lists:zipwith(fun join_field/2, Acc, Other) end,
        Fields, Rest).

%% Dynamic alternatives may retain common fixed bits, never a finite-value claim.
-spec join_field(map(), map()) -> map().
join_field(#{name := Name, type := Type, domain := A},
        #{name := Name, type := Type, domain := B}) ->
    #{name => Name, type => Type, domain => join_domain(A, B)}.

%% Ordinary lowering already bounds entry alternatives; no widening is needed.
-spec join_domain(domain(), domain()) -> domain().
join_domain({values, A}, {values, B}) -> {values, lists:usort(A ++ B)};
join_domain(unknown, _) -> unknown;
join_domain(_, unknown) -> unknown;
join_domain(A, B) ->
    {Mask, Value} = domain_bits(A),
    {OtherMask, OtherValue} = domain_bits(B),
    N = bit_size(Mask),
    <<M:N>> = Mask, <<V:N>> = Value, <<OM:N>> = OtherMask, <<OV:N>> = OtherValue,
    Common = M band OM band bnot(V bxor OV),
    {bits, <<Common:N>>, <<(V band Common):N>>}.

%% Exact alternatives contribute only bits common to every encoded value.
-spec domain_bits(domain()) -> {bitstring(), bitstring()}.
domain_bits({bits, Mask, Value}) -> {Mask, Value};
domain_bits({values, [First | Rest]}) ->
    N = bit_size(First), <<V:N>> = First,
    M = lists:foldl(fun(B, Acc) -> <<Other:N>> = B, Acc band bnot(V bxor Other) end,
        (1 bsl N) - 1, Rest),
    {<<M:N>>, <<(V band M):N>>}.

-doc "Returns a selected-layout axis::bits_from_frame known mask/value for ordinary emitted messages on selected ports. Requires fresh facts and an exact closed internal producer binding. Unknown replies and empty emission retain every bit. This is a conditional value bound, not a contract for arbitrary external frames or a temporal proof.".
-spec frame_bits(facts(), [atom(), ...]) -> #{mask := non_neg_integer(), value := non_neg_integer()}.
frame_bits(Facts, Ports) ->
    case frame_cases(Facts, Ports) of
        Cases = [_ | _] -> xls_message_bits:join([maps:with([mask, value], C) || C <- Cases]);
        _ -> #{mask => 0, value => 0}
    end.

-doc "Returns per-operation ordinary-frame bit bounds for selected emitted ports, or unknown when retained replies are possible. Requires fresh facts and complete physical producer bindings. Schema alternatives with the same operation are joined; no phase, reachability, acceptance or lifetime guarantee follows. A closed empty set is silent, not permission to change incoming frames.".
-spec frame_cases(facts(), [atom(), ...]) -> unknown | [#{op := 0 .. ((1 bsl 8) - 1), mask := non_neg_integer(), value := non_neg_integer()}].
frame_cases(Facts = #{tags := Tags, frame_layout := Layout}, Ports) ->
    case on_ports(Facts, Ports) of
        #{closed := true, schemas := Schemas} ->
            [begin
                Op = maps:get(Tag, Tags),
                Bound = xls_message_bits:frame(Op, Fields, Layout),
                Bound#{op => Op}
            end || #{tag := Tag, fields := Fields} <- Schemas];
        _ -> unknown
    end.
