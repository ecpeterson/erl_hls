-module(hls_process_interface).
-moduledoc """
Owns the source-independent interface facts required by logical topology.

An interface describes a bounded computation by module name, mailbox bound,
ordered output ports, public schema layouts, dispatched schemas, and the
schema union emitted through each port. It contains no process identity,
compiler syntax, source freshness, callback state, selector allocation, or
physical frame layout. Compiler adapters project richer summaries into this
contract once before logical planning.
""".

%% Interface construction and validation.
-export([new/1, validate/1]).
%% Source-independent interface queries.
-export([
    dispatched_schemas/1,
    mailbox_capacity/1,
    module/1,
    output_schemas/2,
    outputs/1,
    schema/2
]).
%% Shared interface contracts.
-export_type([field/0, interface/0, schema/0]).

-doc "One ordered public field with a stable host type descriptor.".
-type field() :: #{name := atom(), type := hls_type:descriptor()}.

-doc "A public message layout. Field maps retain names and semantic type descriptors.".
-type schema() :: #{name := atom(), fields := [field()]}.

-doc "The complete process-free contract consumed by logical topology.".
-type interface() :: #{
    version := 1,
    module := module(),
    mailbox_capacity := pos_integer(),
    outputs := [atom()],
    schemas := [schema()],
    dispatched_schemas := [atom()],
    emitted_schemas := #{atom() => [atom()]}
}.

-doc "Validates and returns a source-independent interface without reordering artifact-significant outputs or schemas.".
-spec new(map()) -> interface().
new(Interface) ->
    ok = validate(Interface),
    Interface.

-doc "Checks shape, uniqueness, bounds, and all schema references; raises a tagged interface error on failure.".
-spec validate(term()) -> ok.
validate(
    Interface = #{
        version := 1,
        module := Module,
        mailbox_capacity := Capacity,
        outputs := Outputs,
        schemas := Schemas,
        dispatched_schemas := Dispatched,
        emitted_schemas := Emitted
    }
) when
    is_atom(Module),
    is_integer(Capacity),
    Capacity > 0,
    is_list(Outputs),
    is_list(Schemas),
    is_list(Dispatched),
    is_map(Emitted)
->
    Required = [
        dispatched_schemas,
        emitted_schemas,
        mailbox_capacity,
        module,
        outputs,
        schemas,
        version
    ],
    Keys = maps:keys(Interface),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} -> error({invalid_process_interface_keys, Missing, Unknown})
    end,
    ok = require_atoms(outputs, Outputs),
    ok = require_unique(outputs, Outputs),
    SchemaNames = [validate_schema(Schema) || Schema <- Schemas],
    ok = require_unique(schemas, SchemaNames),
    ok = require_atoms(dispatched_schemas, Dispatched),
    ok = require_unique(dispatched_schemas, Dispatched),
    ok = require_known_schemas(dispatched_schemas, Dispatched, SchemaNames),
    SortedOutputs = lists:sort(Outputs),
    case lists:sort(maps:keys(Emitted)) of
        SortedOutputs -> ok;
        EmittedPorts -> error({invalid_process_interface_emitted_ports, Outputs, EmittedPorts})
    end,
    maps:foreach(
        fun
            (Port, Names) when is_list(Names) ->
                ok = require_atoms({emitted_schemas, Port}, Names),
                ok = require_unique({emitted_schemas, Port}, Names),
                require_known_schemas({emitted_schemas, Port}, Names, SchemaNames);
            (Port, Names) ->
                error({invalid_process_interface_emitted_schemas, Port, Names})
        end,
        Emitted
    ),
    ok;
validate(#{version := Version}) when Version =/= 1 ->
    error({unsupported_process_interface_version, Version});
validate(Interface) ->
    error({invalid_process_interface, Interface}).

-doc "Returns the schemas accepted by at least one logical dispatch.".
-spec dispatched_schemas(interface()) -> [atom()].
dispatched_schemas(#{dispatched_schemas := Schemas}) ->
    Schemas.

-doc "Returns the positive mailbox bound declared for the computation.".
-spec mailbox_capacity(interface()) -> pos_integer().
mailbox_capacity(#{mailbox_capacity := Capacity}) ->
    Capacity.

-doc "Returns the module that supplies the computation artifact.".
-spec module(interface()) -> module().
module(#{module := Module}) ->
    Module.

-doc "Returns the schemas that may be emitted through `Port`; an unknown port has an empty union.".
-spec output_schemas(interface(), atom()) -> [atom()].
output_schemas(#{emitted_schemas := Emitted}, Port) ->
    maps:get(Port, Emitted, []).

-doc "Returns output ports in their artifact ABI order.".
-spec outputs(interface()) -> [atom()].
outputs(#{outputs := Outputs}) ->
    Outputs.

-doc "Returns one public schema layout or raises the established unknown-schema error.".
-spec schema(interface(), atom()) -> schema().
schema(#{module := Module, schemas := Schemas}, Name) ->
    case [Item || Item = #{name := ItemName} <- Schemas, ItemName =:= Name] of
        [Item] -> Item;
        [] -> error({unknown_hls_actor_schema, Module, Name})
    end.

%% Validate one exact schema while returning its name for uniqueness checks.
-spec validate_schema(term()) -> atom().
validate_schema(Schema = #{name := Name, fields := Fields}) when is_atom(Name), is_list(Fields) ->
    Keys = maps:keys(Schema),
    case {[fields, name] -- Keys, Keys -- [fields, name]} of
        {[], []} -> ok;
        _ -> error({invalid_process_interface_schema_keys, Name, Keys})
    end,
    FieldNames = [validate_field(Name, Field) || Field <- Fields],
    ok = require_unique({schema_fields, Name}, FieldNames),
    Name;
validate_schema(Schema) ->
    error({invalid_process_interface_schema, Schema}).

%% Validate one exact named field and its structural provider descriptor.
-spec validate_field(atom(), term()) -> atom().
validate_field(Schema, Field = #{name := Name, type := Type}) when is_atom(Name) ->
    Keys = maps:keys(Field),
    case {[name, type] -- Keys, Keys -- [name, type]} of
        {[], []} -> ok;
        _ -> error({invalid_process_interface_field_keys, Schema, Name, Keys})
    end,
    ok = validate_descriptor(Type),
    Name;
validate_field(Schema, Field) ->
    error({invalid_process_interface_field, Schema, Field}).

%% Check descriptor structure without loading or invoking its provider.
-spec validate_descriptor(term()) -> ok.
validate_descriptor({hls_type, Module, Name, Args}) when
    is_atom(Module), is_atom(Name), is_list(Args)
->
    lists:foreach(fun validate_type_arg/1, Args);
validate_descriptor(Type) ->
    error({invalid_process_interface_type, Type}).

%% Descriptor parameters are literals, nested descriptors, named fields, or ordered lists.
-spec validate_type_arg(term()) -> ok.
validate_type_arg(Value) when is_integer(Value); is_atom(Value) ->
    ok;
validate_type_arg(Type = {hls_type, _Module, _Name, _Args}) ->
    validate_descriptor(Type);
validate_type_arg({Name, Type}) when is_atom(Name) ->
    validate_descriptor(Type);
validate_type_arg(Args) when is_list(Args) ->
    lists:foreach(fun validate_type_arg/1, Args);
validate_type_arg(Arg) ->
    error({invalid_process_interface_type_argument, Arg}).

%% Require an atom-only name list at the untrusted projection boundary.
-spec require_atoms(term(), list()) -> ok.
require_atoms(Kind, Values) ->
    case lists:all(fun erlang:is_atom/1, Values) of
        true -> ok;
        false -> error({invalid_process_interface_names, Kind, Values})
    end.

%% Require list values to be unique without changing their declared order.
-spec require_unique(term(), list()) -> ok.
require_unique(Kind, Values) ->
    Unique = lists:usort(Values),
    case length(Values) =:= length(Unique) of
        true -> ok;
        false -> error({duplicate_process_interface_values, Kind, Values})
    end.

%% Require every referenced schema to have a declared layout.
-spec require_known_schemas(term(), [atom()], [atom()]) -> ok.
require_known_schemas(Kind, Names, Declared) ->
    case Names -- Declared of
        [] -> ok;
        Unknown -> error({unknown_process_interface_schemas, Kind, Unknown})
    end.
