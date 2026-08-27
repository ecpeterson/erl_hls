-module(xls_pack).
-export([parse_transform/2]).

-define(MAX_TAG_VALUE, 255).  % bounded by tag width in axis header

% -define(debug(X), begin io:format("~w@~w: ~p~n", [?FUNCTION_NAME, ?LINE, X]), X end).
-define(debug(X), X).

replace_anno(Anno, {integer, _OldAnno, Value}) ->
    {integer, Anno, Value};
replace_anno(Anno, {atom, _OldAnno, Value}) ->
    {atom, Anno, Value};
replace_anno(Anno, {remote_type, _OldAnno, [Module, Name, Args]}) ->
    {remote_type, Anno, [
        replace_anno(Anno, Module),
        replace_anno(Anno, Name),
        lists:map(fun(A) -> replace_anno(Anno, A) end, Args)
    ]}.

calls_from_types({remote_type, Anno, [Module, Name, Args]}) ->
    {call,
        Anno,
        {remote, Anno, Module, Name},
        lists:map(fun calls_from_types/1, Args)
    };
calls_from_types(X) -> X.

parse_transform(Forms, _Options) ->
    [FileAttr, ModuleAttr | TailForms] = Forms,
    {BodyForms, EOFForm} = {lists:droplast(TailForms), lists:last(TailForms)},

    PublicStructNames = xls_parse:find_attribute(Forms, xls_tags),
    StateName = xls_parse:state(Forms),
    SerializableStructNames = [StateName | PublicStructNames],
    RewrittenBodyForms = rewrite_record_defaults(
        BodyForms, SerializableStructNames
    ),
    true = length([error | SerializableStructNames]) =< ?MAX_TAG_VALUE,
    ExportAttr = {attribute, element(2, ModuleAttr), export,
        [{pack, 1}, {unpack, 2}, {pack_tag, 1}, {unpack_tag, 1}]
    },
    {eof, Line} = EOFForm,

    PackForm = {function, Line, pack, 1, [
        {clause, Line, [{match, Line, {var, Line, 'Record'}, {record, Line, Tag, []}}], [], [
            {bin, Line, [
                {bin_element, Line,
                    {call, Line, {remote, Line, {atom, Line, xls_type}, {atom, Line, pack}}, [
                        {record_field, Line, {var, Line, 'Record'}, Tag, {atom, Line, FieldAtom}},
                        calls_from_types(replace_anno(Line, Desc))
                    ]},
                    default,
                    [binary]
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
                    [calls_from_types(replace_anno(Line, Desc))
                        ||  {attribute, _L, record, {_T, Fields}} <- [xls_parse:find_record(Forms, Tag)],
                            {typed_record_field, _record_Field, Desc} <- Fields]
            )},
            {match, Line,
                {tuple, Line, [{var, Line, 'Unpacked'}, {var, Line, 'Rest'}]},
                {call, Line,
                      {remote, Line, {atom, Line, xls_gs}, {atom, Line, generic_unpack}},
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

    EmittedForms =
        [FileAttr, ModuleAttr, ExportAttr] ++
        RewrittenBodyForms ++
        [PackForm, UnpackForm, PackTagForm, UnpackTagForm, EOFForm],
    % io:format("~s~n", [[[erl_pp:form(Form), "\n"] || Form <- EmittedForms]]),
    EmittedForms.

rewrite_record_defaults(Forms, SerializableStructNames) ->
    [
        rewrite_record_defaults_in_form(Form, SerializableStructNames)
        || Form <- Forms
    ].

rewrite_record_defaults_in_form(
    RecordForm = {attribute, Line, record, {RecordName, Fields}},
    SerializableStructNames
) ->
    case lists:member(RecordName, SerializableStructNames) of
        true ->
            ok = xls_parse:validate_record_defaults(RecordForm),
            {attribute, Line, record, {
                RecordName,
                [rewrite_record_field_default(Field) || Field <- Fields]
            }};
        false ->
            {attribute, Line, record, {RecordName, Fields}}
    end;
rewrite_record_defaults_in_form(Form, _SerializableStructNames) ->
    Form.

rewrite_record_field_default(
    {typed_record_field,
        {record_field, Line, {atom, AtomLine, FieldName}, _Default},
        Type}
) ->
    ExpandedDefault = {call,
        Line,
        {remote, Line, {atom, Line, xls_type}, {atom, Line, zero}},
        [calls_from_types(replace_anno(Line, Type))]
    },
    {typed_record_field,
        {record_field, Line, {atom, AtomLine, FieldName}, ExpandedDefault},
        Type}.
