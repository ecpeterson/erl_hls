%%%% hls_actor_interface
%%%%
%%%% Queries the provisional interface summary emitted for hls_statem actors.

-module(hls_actor_interface).
-moduledoc """
Reads the narrow, version-3 interface summary emitted by `hls_pack` for an
`hls_statem` module.

When the compiling source remains available, the query re-derives the summary
with the current analyzer and the captured build directory, include paths,
macros, and feature options, and rejects a stale beam. This keeps incremental
builds from silently mixing old interface facts with a newer topology
generator; source-less deployed beams use their validated embedded summary.
Deterministic builds omit source context and use that same embedded-summary
path. The check compares interface facts, not complete callback behavior or an
artifact hash. See `docs/source-context.md` for compilation inputs and limits.

`from_modules/1` resolves each distinct module once into a caller-owned map.
Planning passes use this map across instances, families, or scheduler groups;
no interface cache survives the pass. A later pass rereads current sources.

The summary records only facts already required by the current lowerer:
message record layouts and local selectors, phase-specific cast dispatch, and
source-ordered phase-entry effects. Alternatives form a conservative union by
position, port, and schema; more than one effect may describe a position, but
only the selected alternative occupies it. An effect is unconditional only
when every path has that port and schema at that position and no path uses a
predicate-bearing action there. Batch capacity is the largest path, not the
size of this union. A
dispatch means that the generated actor has a callback group for that schema
and phase; it does not claim that every payload passes the group's patterns and
guards.

The summary also carries the failure source map and callback-state layout. Its packed width is derived
when queried, after custom `hls_type` modules are available; computing it while
the actor's parse transform runs would make compilation depend on incidental
source order. This is the state which a shared scheduler may place in generated
memory. Bounded actor-local reduction state is reported separately, then
colocated in the same scheduler RAM row without becoming a callback-record
field. Mailbox slots, phase, postponement, admission, and pending effects
remain scheduler state and are deliberately not folded into that record.

This is internal compiler data for the phi topology experiment, not a stable
application behavior or a general Erlang protocol description.
""".

-export([
    dispatched_schemas/1,
    dispatched_schemas/2,
    from_module/1,
    from_modules/1,
    initial_effects/1,
    max_entry_effects/1,
    output_schemas/2,
    reduction_storage_width/1,
    schema/2,
    state/1
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
                    verify_current_source(Module, Validated, Attributes);
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

-spec from_modules([module()]) -> #{module() => summary()}.
-doc "Reads each distinct module once for a planning pass; retains no global cache.".
from_modules(Modules) ->
    maps:from_list([{Module, from_module(Module)}
        || Module <- lists:usort(Modules)]).

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
    lists:max([0 | [Order + 1
        || #{order := Order} <- maps:get(entry_effects, Summary)]]).

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

-spec state(summary()) -> map().
-doc "Returns the callback-state record name, fields, and packed width.".
state(Summary) ->
    State = maps:get(state, Summary),
    State#{width => lists:sum([
        hls_type:width(maps:get(type, Field))
        || Field <- maps:get(fields, State)
    ])}.

-spec reduction_storage_width(summary()) -> non_neg_integer().
-doc "Returns the derived packed actor-local reduction width, or zero.".
reduction_storage_width(Summary) ->
    case maps:get(reductions, Summary, none) of
        none -> 0;
        Reduction when is_map(Reduction) ->
            xls_statem_reduction_ir:interface_storage_width(Reduction);
        Reduction ->
            error({invalid_hls_actor_reduction_interface, Reduction})
    end.

validate(Module, Summary = #{
    version := 3,
    module := Module,
    phases := Phases,
    initial_phase := InitialPhase,
    outputs := Outputs,
    mailbox_capacity := Capacity,
    state := State,
    schemas := Schemas,
    dispatches := Dispatches,
    entry_effects := Effects,
    failure_sites := Sites
}) when is_list(Phases), is_list(Outputs),
        is_integer(Capacity), Capacity > 0,
        is_list(Schemas), is_list(Dispatches), is_list(Effects) ->
    true = InitialPhase =:= unknown orelse
        lists:member(InitialPhase, Phases),
    ok = require_unique(interface_phase, Phases),
    ok = require_unique(interface_output, Outputs),
    ok = validate_state(State),
    ok = xls_failure_sites:validate(Sites),
    _ = reduction_storage_width(Summary),
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
validate(Module, #{version := Version}) when Version =/= 3 ->
    error({unsupported_hls_actor_interface_version, Module, Version});
validate(Module, Summary) ->
    error({invalid_hls_actor_interface, Module, Summary}).

validate_state(#{name := Name, fields := [_ | _] = Fields})
        when is_atom(Name) ->
    true = lists:all(
        fun
            (#{name := FieldName, type := Type}) ->
                is_atom(FieldName) andalso is_tuple(Type);
            (_) ->
                false
        end,
        Fields
    ),
    ok;
validate_state(State) ->
    error({state, State}).

validate_behavior(Module, Attributes) ->
    Behaviors =
        proplists:get_all_values(behavior, Attributes) ++
        proplists:get_all_values(behaviour, Attributes),
    case lists:member(hls_statem, lists:append(Behaviors)) of
        true -> ok;
        false -> error({not_an_hls_statem_actor, Module})
    end.

verify_current_source(Module, Summary, Attributes) ->
    CompileInfo = Module:module_info(compile),
    case proplists:get_value(source, CompileInfo, '$missing') of
        Source0 when is_list(Source0); is_binary(Source0) ->
            Source = filename(Source0),
            case filelib:is_regular(Source) of
                true ->
                    Context = case proplists:get_value(
                            hls_source_context, Attributes) of
                        [Captured] when is_map(Captured) -> Captured;
                        _ -> error({missing_hls_source_context, Module})
                    end,
                    Current = validate(
                        Module,
                        xls_parse:actor_interface(Source, Context)
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
