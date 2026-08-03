-module(xls_pack).
-export([parse_transform/2]).

-define(MAX_TAGS, 255).  % bounded by tag width in axis header

% -define(debug(X), begin io:format("~w@~w: ~p~n", [?FUNCTION_NAME, ?LINE, X]), X end).
-define(debug(X), X).

%%%
%%%
%%% parse transform
%%%
%%%

parse_transform(Forms, _Options) ->
    [FileAttr, ModuleAttr | TailForms] = Forms,
    {BodyForms, EOFForm} = {lists:droplast(TailForms), lists:last(TailForms)},

    PublicStructNames = xls_parse:find_attribute(Forms, xls_tags),
    true = length(PublicStructNames) =< ?MAX_TAGS,
    ExportAttr = {attribute, element(2, ModuleAttr), export,
        [{pack, 1}, {unpack, 2}, {pack_tag, 1}, {unpack_tag, 1}]
    },
    {eof, Line} = EOFForm,

    PackForm = {function, Line, pack, 1, [
        {clause, Line, [{match, Line, {var, Line, 'Record'}, {record, Line, Tag, []}}], [], [
            {bin, Line, [
                {bin_element, Line,
                    {record_field, Line, {var, Line, 'Record'}, Tag, {atom, Line, FieldAtom}},
                    {integer, Line, 32},  % TODO: width
                    [little, unsigned, integer]  % TODO: tags
                }
                ||  {attribute, _L, record, {_T, Fields}} <- [xls_parse:find_record(Forms, Tag)],
                    {typed_record_field,
                        {record_field, _1, {atom, _2, FieldAtom}, _Default},
                        {remote_type, _3, [{atom, _4, _Module}, {atom, _5, _Type}, _TypeArgs]}
                    } <- Fields
            ]}
        ]}
        ||  Tag <- PublicStructNames
    ]},

    UnpackForm = {function, Line, unpack, 2, [
        {clause, Line, [{atom, Line, Tag}, {var, Line, 'Binary'}], [], [
            {match, Line, {bin, Line, [
                {bin_element, Line,
                    {var, Line, list_to_atom(string:titlecase(atom_to_list(FieldAtom)))},
                    {integer, Line, 32},  % TODO: width
                    [little, unsigned, integer]  % TODO: descriptors
                }
                ||  {attribute, _L, record, {_T, Fields}} <- [xls_parse:find_record(Forms, Tag)],
                    {typed_record_field,
                        {record_field, _1, {atom, _2, FieldAtom}, _Default},
                        {remote_type, _3, [{atom, _4, _Module}, {atom, _5, _Type}, _TypeArgs]}
                    } <- Fields
                ] ++ [{bin_element, Line, {var, Line, 'Rest'}, default, [binary]}]
            }, {var, Line, 'Binary'}},
            {tuple, Line, [
                {record, Line, Tag, [
                    {record_field, Line,
                        {atom, Line, FieldAtom},
                        {var, Line, list_to_atom(string:titlecase(atom_to_list(FieldAtom)))}
                    }
                    ||  {attribute, _L, record, {_T, Fields}} <- [xls_parse:find_record(Forms, Tag)],
                        {typed_record_field,
                            {record_field, _1, {atom, _2, FieldAtom}, _Default},
                            _Type
                        } <- Fields
                ]},
                {var, Line, 'Rest'}
            ]}
        ]}
        ||  Tag <- PublicStructNames
    ]},

    PackTagForm = {function, Line, pack_tag, 1, [
        {clause, Line, [{atom, Line, Tag}], [], [{integer, Line, Index}]}
        ||  {Index, Tag} <- lists:enumerate([state | PublicStructNames])
    ]},

    UnpackTagForm = {function, Line, unpack_tag, 1, [
        {clause, Line, [{integer, Line, Index}], [], [{atom, Line, Tag}]}
        ||  {Index, Tag} <- lists:enumerate([state | PublicStructNames])
    ]},

    ?debug([FileAttr, ModuleAttr, ExportAttr] ++ BodyForms ++ [PackForm, UnpackForm, PackTagForm, UnpackTagForm, EOFForm]).
