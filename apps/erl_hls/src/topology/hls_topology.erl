-module(hls_topology).
-moduledoc """
Acquires compiler-owned actor summaries for logical topology planning.

The facade loads a topology callback, resolves each distinct actor module once,
projects its compiler summary into `hls_process_interface`, and delegates all
normalization and route resolution to `hls_logical_topology`. Source freshness,
compiler syntax, and richer lowering facts do not cross the core boundary.
""".

%% Compiler acquisition and logical normalization.
-export([from_module/1, normalize/1]).
%% Compiler-summary projection into the shared logical contract.
-export([project_interface/1, validate_interfaces/2]).
%% Source-compatible compact route lookup.
-export([routes_for_instance/3]).
%% Source-compatible compact topology contracts.
-export_type([plan/0, spec/0]).

-doc "An unchecked compact logical-topology term owned by hls_logical_topology.".
-type spec() :: hls_logical_topology:spec().

-doc "A normalized compact logical topology owned by hls_logical_topology.".
-type plan() :: hls_logical_topology:compact_plan().

-doc "Loads `Module:topology/0`, acquires its actor interfaces, and normalizes the returned term.".
-spec from_module(module()) -> plan().
from_module(Module) when is_atom(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} ->
            case erlang:function_exported(Module, topology, 0) of
                true -> normalize(Module:topology());
                false -> error({missing_topology_callback, Module, topology, 0})
            end;
        {error, Reason} ->
            error({topology_module_unavailable, Module, Reason})
    end;
from_module(Module) ->
    error({invalid_topology_module, Module}).

-doc "Acquires each distinct compiler summary once, projects process-free facts, and delegates compact normalization.".
-spec normalize(spec()) -> plan().
normalize(Spec) ->
    Modules = hls_logical_topology:interface_modules(Spec),
    Summaries = hls_actor_interface:from_modules(Modules),
    Interfaces = maps:map(
        fun(_Module, Summary) -> project_interface(Summary) end,
        Summaries
    ),
    hls_logical_topology:normalize(Spec, Interfaces).

-doc "Delegates compact family-route resolution to the core topology authority.".
-spec routes_for_instance(plan(), term(), [non_neg_integer()]) -> [map()].
routes_for_instance(Plan, FamilyId, Coordinates) ->
    hls_logical_topology:routes_for_instance(Plan, FamilyId, Coordinates).

-doc "Projects one source-bound compiler summary into the source-independent communication contract, discarding selectors, syntax, state and physical layout.".
-spec project_interface(hls_actor_interface:summary()) -> hls_process_interface:interface().
project_interface(
    Summary = #{
        module := Module,
        mailbox_capacity := Capacity,
        outputs := Outputs,
        schemas := CompilerSchemas
    }
) ->
    Schemas = [
        #{
            name => maps:get(name, Schema),
            fields => [
                #{name => maps:get(name, Field), type => maps:get(type, Field)}
             || Field <- maps:get(fields, Schema)
            ]
        }
     || Schema <- CompilerSchemas
    ],
    hls_process_interface:new(#{
        version => 1,
        module => Module,
        mailbox_capacity => Capacity,
        outputs => Outputs,
        schemas => Schemas,
        dispatched_schemas => hls_actor_interface:dispatched_schemas(Summary),
        emitted_schemas => maps:from_list([
            {Port, hls_actor_interface:output_schemas(Summary, Port)}
         || Port <- Outputs
        ])
    }).

-doc "Checks that a retained compiler-summary catalog covers exactly the topology modules and projects byte-for-term to its core communication catalog. Physical-only fields remain available to the caller.".
-spec validate_interfaces(
    hls_logical_topology:compact_plan() | hls_logical_topology:materialized_plan(),
    #{module() => hls_actor_interface:summary()}
) -> ok.
validate_interfaces(Plan, Interfaces) when is_map(Interfaces) ->
    Expected = hls_logical_topology:interfaces(Plan),
    ExpectedModules = lists:sort(maps:keys(Expected)),
    ActualModules = lists:sort(maps:keys(Interfaces)),
    case {ExpectedModules -- ActualModules, ActualModules -- ExpectedModules} of
        {[], []} -> ok;
        {Missing, Extra} -> error({compiler_process_interface_catalog, Missing, Extra})
    end,
    maps:foreach(
        fun(Module, Interface) ->
            Required = maps:get(Module, Expected),
            case project_interface(Interface) of
                Required ->
                    ok;
                Projected ->
                    error({compiler_process_interface_mismatch, Module, Required, Projected})
            end
        end,
        Interfaces
    );
validate_interfaces(_Plan, Interfaces) ->
    error({invalid_compiler_process_interface_catalog, Interfaces}).
