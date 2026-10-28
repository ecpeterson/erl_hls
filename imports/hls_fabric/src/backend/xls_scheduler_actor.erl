-module(xls_scheduler_actor).
-moduledoc "Compiles actor source for the channel-scheduler execution backend. Whole-network builders pass retained placement requirements; the compiler supplies checked callbacks and the scheduler renderer adds storage and execution ownership.".
%% Emitted artifacts retain failure metadata for composition and inspection.
-export([to_artifact/1, to_artifact/2]).

%% Byte-only convenience for callers that do not retain metadata.
-export([to_xls/1, to_xls/2]).

-doc "Renders ordinary shared execution and its dedicated service from the same callbacks.".
-spec to_xls(file:filename()) -> binary().
to_xls(Filename) -> to_xls(Filename, #{}).
-doc "Selects shared reduction placement and optional physical observations.".
-spec to_xls(file:filename(), map()) -> binary().
to_xls(Filename, Options) -> xls_emitted:bytes(to_artifact(Filename, Options)).

-doc "Compiles ordinary shared execution with its sealed emitted failure codebook.".
-spec to_artifact(file:filename()) -> xls_emitted:artifact().
to_artifact(Filename) -> to_artifact(Filename, #{}).

-doc "Compiles the selected physical specialization, retaining exact DSLX bytes and its allocated source failure codes. Debug projections must use this result rather than reconstruct metadata from text.".
-spec to_artifact(file:filename(), map()) -> xls_emitted:artifact().
to_artifact(Filename, Options) ->
    case maps:keys(Options) -- [source_options, shared_service, mailbox_debug, direct_actor_debug, state_projection, admission_reductions, direct_collection, gather_collection, frame_payload_words] of
        [] -> ok;
        Unknown -> error({invalid_xls_options, Unknown})
    end,
    Mode = maps:get(shared_service, Options, ordinary),
    case Mode of ordinary -> ok; aggregate_only -> ok; _ -> error({invalid_xls_shared_service, Mode}) end,
    Path = source(Filename),
    Layout = hls_frame_layout:new(maps:get(frame_payload_words, Options, 3)),
    try xls_parse:actor_artifact(Path, maps:get(source_options, Options, []), Layout) of
        Spec ->
            ok = validate_shared_service(Mode, maps:get(reductions, Spec)),
            ok = xls_collection_codegen:validate(Spec, Options),
            ok = xls_direct_collection_codegen:validate(Spec, Options),
            ok = xls_indexed_collection_codegen:validate(Spec, Options),
            Specialized = case maps:find(state_projection, Options) of
                error -> Spec;
                {ok, Projection} ->
                    Context = case maps:get(source_options, Options, []) of
                        C when is_map(C) -> C;
                        Os -> hls_source:options(Path, Os)
                    end,
                    ok = xls_state_projection:validate(Spec, Projection, hls_source:read(Path, Context)),
                    Spec#{state_projection => Projection}
            end,
            xls_scheduler_codegen:artifact(Specialized#{shared_service => Mode,
                admission_reductions => maps:get(admission_reductions, Options, false),
                gather_collection => maps:get(gather_collection, Options, false),
                direct_collection => maps:get(direct_collection, Options, false),
                mailbox_debug => xls_scheduler_observation:enabled(Options),
                direct_actor_debug => xls_actor_observation:enabled(Options)})
    catch error:{unsupported_actor_artifact, _, hls_gs} ->
        case maps:get(direct_collection, Options, false) of
            false -> ok; _ -> error(direct_collection_requires_reduced_statem) end,
        case maps:get(admission_reductions, Options, false) of
            false -> ok; _ -> error(admission_reductions_require_ordinary_reduced_actor) end,
        case maps:get(gather_collection, Options, false) of
            false -> ok; _ -> error(gather_collection_requires_hls_statem) end,
        case maps:is_key(state_projection, Options) of
            true -> error(state_projection_requires_hls_statem); false -> ok end,
        case {Mode, xls_scheduler_observation:enabled(Options)} of
            {ordinary, false} -> xls_parse:to_artifact(Path, maps:with([source_options, direct_actor_debug, frame_payload_words], Options));
            {ordinary, true} -> error(mailbox_debug_requires_hls_statem);
            _ -> error({unsupported_hls_gs_shared_service, Mode})
        end
    end.

%% Requires unambiguous state-independent contributions for aggregate-only delivery.
-spec validate_shared_service('aggregate_only' | 'ordinary','none' | map()) -> 'ok'.
validate_shared_service(ordinary, _Reductions) ->
    ok;
validate_shared_service(aggregate_only, none) ->
    error(aggregate_only_requires_reductions);
validate_shared_service(aggregate_only, #{sites := Sites}) ->
    %% Aggregate-only is a low-level actor artifact: a future topology may
    %% classify a partial schema upstream and send its fallback messages on the
    %% ordinary request port.  Whole-schema capture is therefore proved by the
    %% source-fragment planner, while this boundary only requires that the
    %% aggregate contribution itself can be evaluated without actor state.
    Contributions = [{maps:get(phase, Site), Contribution}
        || Site <- Sites,
           Contribution <- maps:get(contributions, Site)],
    Nontransportable = [
        #{phase => Phase, schema => maps:get(tag, Contribution)}
        || {Phase, Contribution} <- Contributions,
           maps:get(source_transportable, Contribution) =:= false
    ],
    case Nontransportable of
        [] -> ok;
        _ -> error({aggregate_only_nontransportable_contributions,
            Nontransportable})
    end,
    Tags = [maps:get(tag, Contribution)
        || {_Phase, Contribution} <- Contributions],
    case duplicate_values(Tags) of
        [] -> ok;
        Duplicates -> error({aggregate_only_ambiguous_contribution_schemas,
            Duplicates})
    end.

%% Returns repeated values once, using exact map-key equality.
-spec duplicate_values([Value]) -> [Value].
duplicate_values(Values) ->
    duplicate_values(Values, #{}, #{}).

%% Returns repeated values once, using exact map-key equality.
-spec duplicate_values([Value], #{Value => true}, #{Value => true}) -> [Value].
duplicate_values([], _Seen, Duplicates) ->
    lists:sort(maps:keys(Duplicates));
duplicate_values([Value | Rest], Seen, Duplicates) ->
    case maps:is_key(Value, Seen) of
        true -> duplicate_values(Rest, Seen, Duplicates#{Value => true});
        false -> duplicate_values(Rest, Seen#{Value => true}, Duplicates)
    end.

%% Build clients may name either owned fixtures or dependency-owned actor sources.
-spec source(file:filename()) -> file:filename().
source(Filename) ->
    case filelib:is_file(Filename) of
        true -> Filename;
        false -> filename:join(code:lib_dir(erl_hls), Filename)
    end.
