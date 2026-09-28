-module(hls_records).
-moduledoc false.
-export([resolve/1, declarations/2, values/2, used/1, wire_names/1]).

-doc "Resolves nested record field types from this module; rejects recursive layouts and nested wire-tag records.".
-spec resolve([hls_source:form()]) -> [hls_source:form()].
resolve(Forms) ->
    [case Form of
        {attribute, L, record, {Name, Fields}} ->
            {attribute, L, record, {Name, [resolve_field(F, Forms, [Name]) || F <- Fields]}};
        _ -> Form
    end || Form <- Forms].

%% Only field types change; source expressions and their annotations remain intact.
-spec resolve_field(tuple(), [hls_source:form()], [atom()]) -> tuple().
resolve_field({typed_record_field, Field, Type}, Forms, Stack) ->
    {typed_record_field, Field, resolve_type(Type, Forms, Stack)};
resolve_field(Field, _Forms, _Stack) -> Field.

%% A resolved descriptor is self-contained, so downstream codecs need no source lookup.
-spec resolve_type(term(), [hls_source:form()], [atom()]) -> term().
resolve_type({type, L, record, [{atom, _, Name}]}, Forms, Stack) ->
    case lists:member(Name, Stack) of
        true -> error({recursive_hls_record, lists:reverse([Name | Stack])});
        false -> ok
    end,
    case lists:member(Name, wire_names(Forms)) of
        true -> error({nested_hls_wire_record, Name});
        false -> ok
    end,
    {attribute, _, record, {Name, Fields}} = xls_parse:find_record(Forms, Name),
    Descriptor = {hls_type, hls_record, Name, [
        {xls_parse:record_field_name(Field),
            hls_type:descriptor(resolve_type(Type, Forms, [Name | Stack]))}
        || {typed_record_field, Field, Type} <- Fields]},
    case length(Fields) =:= length(element(4, Descriptor)) of
        true -> ok;
        false -> error({untyped_nested_hls_record, Name})
    end,
    {hls_record_type, L, Descriptor};
resolve_type({type, _, record, _} = Type, _Forms, _Stack) ->
    error({unsupported_hls_record_type, Type});
resolve_type({hls_record_type, _, _} = Type, _Forms, _Stack) -> Type;
resolve_type(Tuple, Forms, Stack) when is_tuple(Tuple) ->
    list_to_tuple([resolve_type(X, Forms, Stack) || X <- tuple_to_list(Tuple)]);
resolve_type(List, Forms, Stack) when is_list(List) ->
    [resolve_type(X, Forms, Stack) || X <- List];
resolve_type(Value, _Forms, _Stack) -> Value.

-doc "Returns dependency-ordered declarations for wire records and reachable internal values.".
-spec declarations([hls_source:form()], [atom()]) -> [hls_source:record_declaration()].
declarations(Forms, Roots) ->
    Extra = case xls_parse:find_optional_attribute(Forms, hls_value_records) of
        {ok, Names} -> Names;
        none -> []
    end,
    {_, Reversed} = lists:foldl(fun(Name, Acc) -> visit(Name, Forms, Acc) end,
        {#{}, []}, Roots ++ Extra),
    lists:reverse(Reversed).

%% Layout cycles were rejected during resolution; each declaration is emitted once.
-spec visit(atom(), [hls_source:form()], {map(), [tuple()]}) -> {map(), [tuple()]}.
visit(Name, _Forms, {Seen, _} = Acc) when is_map_key(Name, Seen) -> Acc;
visit(Name, Forms, {Seen, Records}) ->
    Record = xls_parse:find_record(Forms, Name),
    Dependencies = nested_names(Record),
    {Next, Ordered} = lists:foldl(fun(N, Acc) -> visit(N, Forms, Acc) end,
        {Seen#{Name => true}, Records}, Dependencies),
    {Next, [Record | Ordered]}.

%% Descriptor traversal includes records nested inside fixed-size collections.
-spec nested_names(term()) -> [atom()].
nested_names({hls_type, hls_record, Name, Fields}) -> [Name | nested_names(Fields)];
nested_names(Tuple) when is_tuple(Tuple) -> nested_names(tuple_to_list(Tuple));
nested_names(List) when is_list(List) -> lists:usort(lists:append([nested_names(X) || X <- List]));
nested_names(_) -> [].

-doc "Marks internal record expressions and patterns as untagged values after literal typing.".
-spec values(term(), [atom()]) -> term().
values({record, L, Name, Fields}, Wire) when is_atom(Name) ->
    {record, L, representation(Name, Wire), values(Fields, Wire)};
values({record, L, Base, Name, Fields}, Wire) when is_atom(Name) ->
    {record, L, values(Base, Wire), representation(Name, Wire), values(Fields, Wire)};
values({record_field, L, Base, Name, Field}, Wire) when is_atom(Name) ->
    {record_field, L, values(Base, Wire), representation(Name, Wire), Field};
values(Tuple, Wire) when is_tuple(Tuple) ->
    list_to_tuple([values(X, Wire) || X <- tuple_to_list(Tuple)]);
values(List, Wire) when is_list(List) -> [values(X, Wire) || X <- List];
values(Value, _Wire) -> Value.

%% Top-level callback records retain their established tagged representation.
-spec representation(atom(), [atom()]) -> atom() | {value, atom()}.
representation(Name, Wire) ->
    case lists:member(Name, Wire) of true -> Name; false -> {value, Name} end.

-doc "Collects explicitly marked internal record values in prepared callback/helper syntax.".
-spec used(term()) -> [atom()].
used({value, Name}) when is_atom(Name) -> [Name];
used(Tuple) when is_tuple(Tuple) -> used(tuple_to_list(Tuple));
used(List) when is_list(List) -> lists:usort(lists:append([used(X) || X <- List]));
used(_) -> [].

-doc "Returns callback records and the existing private reduction accumulator tags.".
-spec wire_names([hls_source:form()]) -> [atom()].
wire_names(Forms) ->
    lists:usort([xls_parse:state(Forms) | xls_parse:find_tags(Forms)] ++ accumulator_names(Forms)).

%% The literal seed identifies the accumulator before reduction analysis runs.
-spec accumulator_names(term()) -> [atom()].
accumulator_names({tuple, _, [{atom, _, open_reduction}, _, _, _,
        {tuple, _, [{atom, _, commutative_monoid}, {record, _, Name, _}]}]}) -> [Name];
accumulator_names(Tuple) when is_tuple(Tuple) -> accumulator_names(tuple_to_list(Tuple));
accumulator_names(List) when is_list(List) -> lists:usort(lists:append([accumulator_names(X) || X <- List]));
accumulator_names(_) -> [].
