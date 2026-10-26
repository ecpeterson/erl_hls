-module(xls_phase_values).
-moduledoc "Infers small scalar value sets at successful actor callback boundaries. Facts are source-bound, field-wise overapproximations, not protocol or progress proofs.".
-export([from_file/2, from_file/3, analyze/2, validate/3, manifest/1, field/3]).
-export_type([facts/0, domain/0]).

-doc "A finite scalar set, an unreachable phase (empty set), or unknown; sets widen to unknown above sixteen values.".
-type domain() :: unknown | [integer() | atom()].
-doc "Source- and analyzer-bound phase marginals; only the checked normal callback execution model may consume them.".
-opaque facts() :: #{version := 1, frame_layout := hls_frame_layout:layout(), source_sha256 := binary(), analyzer_md5 := binary(),
    evaluator_md5 := binary(), data := atom(), phases := [atom()], fields := map(), limitations := [term()]}.

-doc "Runs ordinary validation and then derives successful committed-state marginals. Does not alter the ordinary artifact or assume valid incoming messages. Failing callbacks are terminal and cannot establish a later live state.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context()) ->
    {xls_actor_codegen:spec(), facts()}.
from_file(File, Options) -> from_file(File, Options, hls_frame_layout:default()).

-doc "Derives committed-state marginals after ordinary validation under the selected frame capacity.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context(),
    hls_frame_layout:layout()) -> {xls_actor_codegen:spec(), facts()}.
from_file(File, Options, Layout) ->
    {ok, Source} = hls_source:parse_file(File, Options),
    Phases = hls_source:find_attribute(Source, hls_phases),
    Spec = xls_statem_lower:artifact(File, Source, Phases, Layout),
    {Spec, analyze(Source, Spec)}.

-doc "Analyzes exactly the source of a successfully lowered artifact. Internal entry point: the caller must not combine unrelated source and Spec values.".
-spec analyze([hls_source:form()], xls_actor_codegen:spec()) -> facts().
analyze(Source, #{data_name := Data, phases := Phases, frame_layout := Layout}) ->
    Forms = hls_records:resolve(Source),
    C = xls_phase_eval:context(Forms),
    {attribute, _, record, {Data, Fields}} = hls_records:find(Forms, Data),
    Results = [{hls_records:field_name(F), infer(hls_records:field_name(F),
        Data, Phases, Forms, C)} || {typed_record_field, F, _} <- Fields],
    #{version => 1, frame_layout => Layout, source_sha256 => crypto:hash(sha256, term_to_binary(Source, [deterministic])),
        analyzer_md5 => ?MODULE:module_info(md5), evaluator_md5 => xls_phase_eval:module_info(md5),
        data => Data, phases => Phases,
        fields => maps:from_list([{F, D} || {F, {D, _}} <- Results]),
        limitations => lists:usort([L || {_, {_, L}} <- Results, L =/= none])}.

-doc "Recomputes the complete certificate against source, includes, preprocessing options and analyzer implementation; rejects edited or stale facts.".
-spec validate(file:filename(), [hls_source:option()] | hls_source:context(), facts()) -> ok.
validate(File, Options, Facts = #{frame_layout := Layout}) ->
    {_, Current} = from_file(File, Options, Layout),
    case Facts =:= Current of true -> ok; false -> error(stale_phase_values) end.

-doc "Returns the conservative values of one stored field on entry to a phase callback. Empty means no successful path reached that phase in this abstraction, not permission to erase arbitrary-input behavior.".
-spec field(facts(), atom(), atom()) -> domain().
field(#{fields := Fs}, Phase, Name) -> maps:get(Phase, maps:get(Name, Fs)).

-doc "Serializes source identity and inferred domains, including precision losses. Arithmetic/provider results are unknown; state-field correlations and event scheduling are not inferred.".
-spec manifest(facts()) -> map().
manifest(Facts) ->
    maps:map(fun(K, V) -> case lists:member(K, [source_sha256, analyzer_md5, evaluator_md5]) of
        true -> binary:encode_hex(V, lowercase); false -> V end end, Facts).

%% Independent marginals avoid implying correlations between stored fields.
%% Any unsupported operation or resource limit invalidates the whole field.
-spec infer(atom(), atom(), [atom()], [hls_source:form()], map()) -> {map(), term()}.
infer(Field, Data, Phases, Forms, C) ->
    Empty = maps:from_list([{P, []} || P <- Phases]),
    try
        Initial = lists:foldl(fun({V, S}, Acc) ->
            case xls_phase_eval:concrete(V, S) of
                {tuple, [ok, P, D]} -> add(P, D, Field, Data, Acc);
                _ -> throw({phase_analysis, unknown_initial_state})
            end
        end, Empty, xls_phase_eval:call({init, 1}, [{nil}], C)),
        Callbacks = [{P, Cl} || {function, _, P, 3, Cs} <- Forms,
            lists:member(P, Phases), Cl <- Cs],
        {close(Initial, Field, Data, Callbacks, C, 128), none}
    catch throw:{phase_analysis, Why} -> {maps:map(fun(_, _) -> unknown end, Empty), Why} end.

%% Every phase admits entry and event callbacks in any order. This includes
%% impossible schedules and preserves facts only if that larger system does.
-spec close(map(), atom(), atom(), [{atom(), term()}], map(), non_neg_integer()) -> map().
close(_, _, _, _, _, 0) -> throw({phase_analysis, iteration_limit});
close(Domains, Field, Data, Callbacks, C, Fuel) ->
    Next = lists:foldl(fun({P, Clause}, Acc) ->
        Values = case maps:get(P, Domains) of unknown -> [xls_phase_eval:unknown()]; Vs -> Vs end,
        lists:foldl(fun(V, More) ->
            {record, Data, Fs} = xls_phase_eval:record(Data, C),
            Input = {record, Data, Fs#{Field := V}},
            {clause, _, [Event | _], _, _} = Clause,
            Kind = case Event of {atom, _, enter} -> enter; _ -> event end,
            Results = xls_phase_eval:clause(Clause,
                [xls_phase_eval:unknown(), xls_phase_eval:unknown(), Input], C),
            lists:foldl(fun({Out, S}, Last) ->
                result(Kind, P, xls_phase_eval:concrete(Out, S), Field, Data, Last)
            end, More, Results)
        end, Acc, Values)
    end, Domains, Callbacks),
    case Next =:= Domains of true -> Next; false -> close(Next, Field, Data, Callbacks, C, Fuel - 1) end.

%% Explicit failure and evaluation failure cannot publish a new live machine.
%% Unknown directives do not justify deleting a possible state transition.
-spec result(atom(), atom(), xls_phase_eval:value(), atom(), atom(), map()) -> map().
result(enter, P, {tuple, [D, _Effects]}, F, Data, Ds) -> add(P, D, F, Data, Ds);
result(event, _, {tuple, [_, _, fail]}, _, _, Ds) -> Ds;
result(event, P, {tuple, [repeat_phase, D, consume]}, F, Data, Ds) -> add(P, D, F, Data, Ds);
result(event, _, {tuple, [P, D, _Directive]}, F, Data, Ds) -> add(P, D, F, Data, Ds);
result(_, _, _, _, _, _) -> throw({phase_analysis, unsupported_callback_result}).

%% Nonrecord or dynamically selected phases fail closed, rather than silently
%% omitting the return. Unknown field values monotonically erase finite facts.
-spec add(atom(), xls_phase_eval:value(), atom(), atom(), map()) -> map().
add(P, {record, Data, Fs}, F, Data, Ds) when is_map_key(P, Ds) ->
    V = maps:get(F, Fs),
    D = case is_integer(V) orelse is_atom(V) of true -> [V]; false -> unknown end,
    Ds#{P := join(maps:get(P, Ds), D)};
add(_, _, _, _, _) -> throw({phase_analysis, unknown_committed_state}).

%% A finite-height widening bounds inference independently of actor histories.
-spec join(domain(), domain()) -> domain().
join(unknown, _) -> unknown;
join(_, unknown) -> unknown;
join(A, B) -> case lists:usort(A ++ B) of S when length(S) =< 16 -> S; _ -> unknown end.
