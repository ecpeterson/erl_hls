-module(hls_pack).
-export([parse_transform/2]).

% -define(debug(X), begin io:format("~w@~w: ~p~n", [?FUNCTION_NAME, ?LINE, X]), X end).
-define(debug(X), X).

-doc "Generates tagged record codecs and expands typed zero defaults, including acyclic internal record fields.".
-spec parse_transform([hls_source:form()], [atom() | tuple()]) -> [hls_source:form()].
parse_transform(Forms0, Options) ->
    Context = hls_source:from_forms(Forms0, Options),
    %% Source-reader annotations carry preprocessing facts into compile:forms
    %% too. Emit one context attribute, subject to deterministic-build rules.
    OriginalForms = [F || F <- Forms0, not is_source_context(F)],
    Forms = hls_records:resolve(OriginalForms),
    [FileAttr, ModuleAttr | TailForms] = OriginalForms,
    {BodyForms, EOFForm} = {lists:droplast(TailForms), lists:last(TailForms)},

    ok = xls_names:wire_tags(Forms),
    PublicStructNames = xls_parse:find_tags(Forms),
    StateName = xls_parse:state(Forms),
    AnalysisForms = Forms ++ [{attribute, element(2, ModuleAttr),
        hls_source_context, Context}],
    InterfaceAttributes = actor_interface_attributes(AnalysisForms, ModuleAttr),
    ServiceAttributes = service_contract_attributes(AnalysisForms, ModuleAttr),
    SourceAttributes = case InterfaceAttributes of
        [] -> [];
        [_] -> hls_source:capture(AnalysisForms, Options)
    end,
    SerializableStructNames = [StateName | PublicStructNames],
    NestedRecords = hls_records:declarations(Forms, SerializableStructNames),
    [xls_parse:validate_record_defaults(R) || R <- NestedRecords],
    RewrittenBodyForms = rewrite_record_defaults(BodyForms, Forms),
    ExportAttr = {attribute, element(2, ModuleAttr), export,
        [
            {pack, 1},
            {unpack, 2},
            {pack_tag, 1},
            {unpack_tag, 1},
            {pack_width, 1}
        ]
    },
    {eof, Line} = EOFForm,

    PackForm = {function, Line, pack, 1, [
        {clause, Line, [{match, Line, {var, Line, 'Record'}, {record, Line, Tag, []}}], [], [
            {bin, Line, [
                {bin_element, Line,
                    {call, Line, {remote, Line, {atom, Line, hls_type}, {atom, Line, pack}}, [
                        {record_field, Line, {var, Line, 'Record'}, Tag, {atom, Line, FieldAtom}},
                        descriptor_expression(hls_type:descriptor(Desc), Line)
                    ]},
                    default,
                    [bitstring]
                }
                ||  {attribute, _L, record, {_T, Fields}} <- [xls_parse:find_record(Forms, Tag)],
                    {typed_record_field, Field, Desc} <- Fields,
                    FieldAtom <- [xls_parse:record_field_name(Field)]
            ]}
        ]}
        ||  Tag <- SerializableStructNames
    ]},

    UnpackForm = {function, Line, unpack, 2, [
        {clause, Line, [{atom, Line, Tag}, {var, Line, 'Binary'}], [],
            %% TODO: add an unpacker for errors
            %% TODO: send errors back as signals rather than messages
            [
            {match, Line, {var, Line, 'Descriptors'},
                lists:foldr(
                    fun(Call, Acc) -> {cons, Line, Call, Acc} end,
                    {nil, Line},
                    [descriptor_expression(hls_type:descriptor(Desc), Line)
                        ||  {attribute, _L, record, {_T, Fields}} <- [xls_parse:find_record(Forms, Tag)],
                            {typed_record_field, _record_Field, Desc} <- Fields]
            )},
            {match, Line,
                {tuple, Line, [{var, Line, 'Unpacked'}, {var, Line, 'Rest'}]},
                {call, Line,
                      {remote, Line, {atom, Line, hls_gs}, {atom, Line, generic_unpack}},
                      [{var, Line, 'Descriptors'}, {var, Line, 'Binary'}]}},
            {tuple, Line,
                [{call, Line,
                       {atom, Line, list_to_tuple},
                       [{cons, Line, {atom, Line, Tag}, {var, Line, 'Unpacked'}}]},
                 {var, Line, 'Rest'}]}
        ]}
        ||  Tag <- SerializableStructNames
    ]},

    PackTagForm = {function, Line, pack_tag, 1, [
        {clause, Line, [{atom, Line, Tag}], [], [{integer, Line, Index}]}
        ||  {Index, Tag} <- lists:enumerate([error, StateName | PublicStructNames])
    ]},

    UnpackTagForm = {function, Line, unpack_tag, 1, [
        {clause, Line, [{integer, Line, Index}], [], [{atom, Line, Tag}]}
        ||  {Index, Tag} <- lists:enumerate([error, StateName | PublicStructNames])
    ]},

    PackWidthForm = {function, Line, pack_width, 1, [
        {clause, Line, [{atom, Line, Tag}], [], [
            record_width_expression(Forms, Tag, Line)
        ]}
        || Tag <- SerializableStructNames
    ]},

    EmittedForms =
        [FileAttr, ModuleAttr, ExportAttr] ++
        InterfaceAttributes ++ ServiceAttributes ++ SourceAttributes ++
        RewrittenBodyForms ++
        [
            PackForm,
            UnpackForm,
            PackTagForm,
            UnpackTagForm,
            PackWidthForm,
            EOFForm
        ],
    % io:format("~s~n", [[[erl_pp:form(Form), "\n"] || Form <- EmittedForms]]),
    EmittedForms.

is_source_context({attribute, _, hls_source_context, _}) -> true;
is_source_context(_) -> false.

%% Embed immediate or retained-server contracts for source-independent host proxies.
-spec service_contract_attributes([hls_source:form()], tuple()) -> [tuple()].
service_contract_attributes(Forms, {attribute, Line, module, _}) ->
    case xls_parse:find_optional_attribute(Forms, hls_phases) of
        {ok, _} ->
            case xls_parse:find_optional_attribute(Forms, hls_pending_calls) of
                none -> [];
                {ok, _} -> [{attribute, Line, hls_service_contract,
                    hls_service_contract:from_forms(Forms)}]
            end;
        none ->
            case lists:any(fun
                ({function, _, handle_call, Arity, _}) when Arity =:= 2; Arity =:= 3 -> true;
                ({function, _, handle_cast, 2, _}) -> true;
                (_) -> false
            end, Forms) of
                true -> [{attribute, Line, hls_service_contract,
                    hls_service_contract:from_forms(Forms)}];
                false -> []
            end
    end.

%% Sum provider widths after resolving nested records in the source context.
-spec record_width_expression([hls_source:form()], atom(), erl_anno:location()) -> erl_parse:abstract_expr().
record_width_expression(Forms, Tag, Location) ->
    Line = erl_anno:new(Location),
    {attribute, _RecordLine, record, {_Tag, Fields}} =
        xls_parse:find_record(Forms, Tag),
    lists:foldl(
        fun({typed_record_field, _Field, Descriptor}, Sum) ->
            Width = {call,
                Line,
                {remote,
                    Line,
                    {atom, Line, hls_type},
                    {atom, Line, width}},
                [descriptor_expression(hls_type:descriptor(Descriptor), Line)]
            },
            {op, Line, '+', Sum, Width}
        end,
        {integer, Line, 0},
        Fields
    ).

actor_interface_attributes(Forms, ModuleAttr) ->
    case xls_parse:find_optional_attribute(Forms, hls_phases) of
        {ok, PhaseNames} ->
            %% Interface inference validates only the structurally observable
            %% HLS subset; lowering callback expressions to DSLX happens later.
            %% A CPU-valid actor outside the structural subset must retain the
            %% compilation behavior it had before summaries existed, and a
            %% topology which selects it will report the missing summary.
            try xls_statem_lower:interface(Forms, PhaseNames) of
                Interface ->
                    [{attribute,
                        element(2, ModuleAttr),
                        hls_actor_interface,
                        Interface}]
            catch
                error:_Reason -> []
            end;
        none ->
            []
    end.

%% Expand typed zeros without changing the source-level record type annotations.
-spec rewrite_record_defaults([tuple()], [hls_source:form()]) -> [tuple()].
rewrite_record_defaults(Body, Resolved) ->
    [rewrite_record_defaults_in_form(Form, Resolved) || Form <- Body].

%% Unrelated ordinary Erlang records retain their explicit defaults.
-spec rewrite_record_defaults_in_form(tuple(), [hls_source:form()]) -> tuple().
rewrite_record_defaults_in_form({attribute, Line, record, {Name, Fields}}, Resolved) ->
    {attribute, _, record, {Name, Types}} = xls_parse:find_record(Resolved, Name),
    {attribute, Line, record, {Name, [rewrite_record_field_default(Field, Type)
        || {Field, Type} <- lists:zip(Fields, Types)]}};
rewrite_record_defaults_in_form(Form, _Resolved) -> Form.

%% A nested descriptor restores each field's record tag only on the BEAM.
-spec rewrite_record_field_default(tuple(), tuple()) -> tuple().
rewrite_record_field_default({typed_record_field,
        {record_field, Line, Name, Default}, Type} = Field,
        {typed_record_field, _, ResolvedType}) ->
    case xls_parse:is_zero_default(Default) of
        true ->
            Expanded = {call, Line,
                {remote, Line, {atom, Line, hls_type}, {atom, Line, zero}},
                [descriptor_expression(hls_type:descriptor(ResolvedType), Line)]},
            {typed_record_field, {record_field, Line, Name, Expanded}, Type};
        false -> Field
    end;
rewrite_record_field_default(Field, _Resolved) -> Field.

%% Keep provider constructor validation on the host, including inside record fields.
-spec descriptor_expression(hls_type:arg(), erl_anno:anno() | erl_anno:location()) -> tuple().
descriptor_expression({hls_type, hls_record, Name, Fields}, Line) ->
    {tuple, Line, [{atom, Line, hls_type}, {atom, Line, hls_record}, {atom, Line, Name},
        lists:foldr(fun({Field, Type}, Tail) ->
            {cons, Line, {tuple, Line, [{atom, Line, Field}, descriptor_expression(Type, Line)]}, Tail}
        end, {nil, Line}, Fields)]};
descriptor_expression({hls_type, Module, Name, Args}, Line) ->
    {call, Line, {remote, Line, {atom, Line, Module}, {atom, Line, Name}},
        [descriptor_expression(Arg, Line) || Arg <- Args]};
descriptor_expression(Value, Line) -> erl_parse:abstract(Value, erl_anno:location(Line)).
