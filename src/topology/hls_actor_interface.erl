%%%% hls_actor_interface
%%%%
%%%% Queries the provisional interface summary emitted for hls_statem actors.

-module(hls_actor_interface).
-moduledoc """
Reads the narrow, version-0 interface summary emitted by `hls_pack` for an
`hls_statem` module.

When the compiling source remains available, the query re-derives the summary
with the current analyzer and rejects a stale beam. This keeps incremental
builds from silently mixing old interface facts with a newer topology
generator; source-less deployed beams use their validated embedded summary.

The summary records only facts already required by the current lowerer:
message record layouts and local selectors, phase-specific cast dispatch, and
source-ordered phase-entry effects. A dispatch means that the generated actor
has a callback group for that schema and phase; it does not claim that every
payload passes the group's patterns and guards.

This is internal compiler data for the phi topology experiment, not a stable
application behavior or a general Erlang protocol description.
""".

-export([
    dispatched_schemas/1,
    dispatched_schemas/2,
    from_module/1,
    initial_effects/1,
    max_entry_effects/1,
    output_schemas/2,
    schema/2
]).
-export_type([summary/0]).

-type summary() :: map().

-spec from_module(module()) -> summary().
-doc "Loads and validates the interface emitted with one hls_statem module.".
from_module(Module) when is_atom(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} ->
            Attributes = Module:module_info(attributes),
            ok = validate_behavior(Module, Attributes),
            case proplists:get_value(
                hls_actor_interface,
                Attributes,
                '$missing'
            ) of
                [Summary] when is_map(Summary) ->
                    Validated = validate(Module, Summary),
                    verify_current_source(Module, Validated);
                '$missing' ->
                    error({missing_hls_actor_interface, Module});
                Value ->
                    error({invalid_hls_actor_interface_attribute,
                        Module, Value})
            end;
        {error, Reason} ->
            error({hls_actor_module_unavailable, Module, Reason})
    end;
from_module(Module) ->
    error({invalid_hls_actor_module, Module}).

-spec dispatched_schemas(summary()) -> [atom()].
-doc "Returns schemas with at least one phase-specific cast dispatch.".
dispatched_schemas(Summary) ->
    lists:usort([
        maps:get(schema, Dispatch)
        || Dispatch <- maps:get(dispatches, Summary)
    ]).

-spec dispatched_schemas(summary(), atom()) -> [atom()].
-doc "Returns schemas dispatched in `Phase`.".
dispatched_schemas(Summary, Phase) ->
    lists:usort([
        maps:get(schema, Dispatch)
        || Dispatch <- maps:get(dispatches, Summary),
           maps:get(phase, Dispatch) =:= Phase
    ]).

-spec output_schemas(summary(), atom()) -> [atom()].
-doc "Returns the schema union emitted through `Port`.".
output_schemas(Summary, Port) ->
    lists:usort([
        maps:get(schema, Effect)
        || Effect <- maps:get(entry_effects, Summary),
           maps:get(port, Effect) =:= Port
    ]).

-spec initial_effects(summary()) -> [map()].
-doc "Returns source-ordered effects of the statically known initial phase.".
initial_effects(Summary) ->
    case maps:get(initial_phase, Summary) of
        unknown ->
            error({unknown_hls_actor_initial_phase,
                maps:get(module, Summary)});
        Phase ->
            [
                Effect
                || Effect <- maps:get(entry_effects, Summary),
                   maps:get(phase, Effect) =:= Phase
            ]
    end.

-spec max_entry_effects(summary()) -> non_neg_integer().
-doc "Returns the largest source-ordered effect list of any phase entry.".
max_entry_effects(Summary) ->
    Effects = maps:get(entry_effects, Summary),
    lists:max([
        length([
            Effect
            || Effect <- Effects,
               maps:get(phase, Effect) =:= Phase
        ])
        || Phase <- maps:get(phases, Summary)
    ]).

-spec schema(summary(), atom()) -> map().
-doc "Looks up one public message schema by record name.".
schema(Summary, Name) ->
    case [
        Item
        || Item <- maps:get(schemas, Summary),
           maps:get(name, Item) =:= Name
    ] of
        [Item] -> Item;
        [] -> error({unknown_hls_actor_schema,
            maps:get(module, Summary), Name})
    end.

validate(Module, Summary = #{
    version := 0,
    module := Module,
    phases := Phases,
    initial_phase := InitialPhase,
    outputs := Outputs,
    mailbox_capacity := Capacity,
    schemas := Schemas,
    dispatches := Dispatches,
    entry_effects := Effects
}) when is_list(Phases), is_list(Outputs),
        is_integer(Capacity), Capacity > 0,
        is_list(Schemas), is_list(Dispatches), is_list(Effects) ->
    true = InitialPhase =:= unknown orelse
        lists:member(InitialPhase, Phases),
    ok = require_unique(interface_phase, Phases),
    ok = require_unique(interface_output, Outputs),
    SchemaNames = [maps:get(name, Schema) || Schema <- Schemas],
    Selectors = [maps:get(selector, Schema) || Schema <- Schemas],
    ok = require_unique(interface_schema, SchemaNames),
    ok = require_unique(interface_selector, Selectors),
    ok = lists:foreach(
        fun(#{schema := Schema, phase := Phase}) ->
            true = lists:member(Schema, SchemaNames),
            true = lists:member(Phase, Phases)
        end,
        Dispatches
    ),
    ok = lists:foreach(
        fun(#{schema := Schema, phase := Phase, port := Port,
                order := Order}) ->
            true = lists:member(Schema, SchemaNames),
            true = lists:member(Phase, Phases),
            true = lists:member(Port, Outputs),
            true = is_integer(Order) andalso Order >= 0
        end,
        Effects
    ),
    Summary;
validate(Module, #{version := Version}) when Version =/= 0 ->
    error({unsupported_hls_actor_interface_version, Module, Version});
validate(Module, Summary) ->
    error({invalid_hls_actor_interface, Module, Summary}).

validate_behavior(Module, Attributes) ->
    Behaviors =
        proplists:get_all_values(behavior, Attributes) ++
        proplists:get_all_values(behaviour, Attributes),
    case lists:member(hls_statem, lists:append(Behaviors)) of
        true -> ok;
        false -> error({not_an_hls_statem_actor, Module})
    end.

verify_current_source(Module, Summary) ->
    CompileInfo = Module:module_info(compile),
    case proplists:get_value(source, CompileInfo, '$missing') of
        Source0 when is_list(Source0); is_binary(Source0) ->
            Source = filename(Source0),
            case filelib:is_regular(Source) of
                true ->
                    Current = validate(
                        Module,
                        xls_parse:actor_interface(Source)
                    ),
                    case Current =:= Summary of
                        true -> Summary;
                        false -> error({stale_hls_actor_interface,
                            Module, Source})
                    end;
                false ->
                    Summary
            end;
        '$missing' ->
            Summary
    end.

filename(Source) when is_binary(Source) -> binary_to_list(Source);
filename(Source) -> Source.

require_unique(Kind, Values) ->
    case length(Values) =:= length(lists:usort(Values)) of
        true -> ok;
        false -> error({duplicate_hls_actor_interface_value, Kind, Values})
    end.
