-module(source_contracts).
-moduledoc "Extract documentation and specification gaps from unexpanded Erlang source.".
-export([main/0]).

%% A diagnostic is keyed by declaration identity; fingerprints track changed declarations.
-type finding() :: #{path := binary(), line := integer(), id := binary(),
                     rule := binary(), fingerprint := binary(), reason => binary()}.
%% Clean files participate in module uniqueness just as files with missing contracts do.
-type file_audit() :: #{path := binary(), module := binary() | null,
                        module_line := integer(), findings := [finding()]}.

-doc "Print JSON file inventories and diagnostics for paths passed after the VM's -- separator.".
-spec main() -> no_return().
main() ->
    Files = [scan(Path) || Path <- init:get_plain_arguments()],
    io:put_chars(json:encode(Files)),
    halt().

%% Parse without expanding macros so all conditional branches remain visible.
-spec scan(string()) -> file_audit().
scan(Path) ->
    {ok, Bytes} = file:read_file(Path),
    Lines = string:split(unicode:characters_to_list(Bytes), "\n", all),
    case epp_dodger:parse_file(Path) of
        {ok, Parsed} ->
            {ok, Tokens, _} = erl_scan:string(unicode:characters_to_list(Bytes)),
            {Forms, RawLines} = recover_macros(Path, Parsed, Tokens),
            Exports = exports(Forms, export),
            Types = exports(Forms, export_type),
            All = lists:any(fun(F) ->
                case attribute(F) of
                    {compile, export_all} -> true;
                    {compile, Options} when is_list(Options) -> lists:member(export_all, Options);
                    _ -> false
                end
            end, Forms),
            Specs = maps:from_list([{Key, F} || F <- Forms,
                {spec, {Key, _}} <- [attribute(F)]]),
            Context = #{path => Path, lines => Lines, exports => Exports,
                        types => Types, all => All, specs => Specs, tokens => Tokens, raw_lines => RawLines},
            file_audit(Path, Forms, inspect(Forms, Context, [], []));
        {error, _} -> file_audit(Path, [], [finding(Path, 1, <<"file">>, <<"parse">>, Bytes)])
    end.

%% Only one literal module attribute gives an Erlang file a movable identity.
%% Headers and unresolved module macros retain path identity; no basename is inferred.
-spec file_audit(string(), [erl_syntax:syntaxTree()], [finding()]) -> file_audit().
file_audit(Path, Forms, Findings) ->
    Modules = [F || F <- Forms, filename:extension(Path) =:= ".erl",
        erl_syntax:type(F) =:= attribute,
        erl_syntax:atom_value(erl_syntax:attribute_name(F)) =:= module],
    {Module, ModuleLine, Errors} = case Modules of
        [Form] ->
            case erl_syntax:attribute_arguments(Form) of
                [Name] ->
                    case erl_syntax:type(Name) of
                        atom -> {atom_to_binary(erl_syntax:atom_value(Name), utf8), line(Form), []};
                        _ -> {null, line(Form), []}
                    end;
                _ -> {null, line(Form), []}
            end;
        [] -> {null, 1, []};
        [First | _] ->
            Error = (finding(Path, line(First), <<"module">>, <<"module_identity">>,
                [formatted(F) || F <- Modules]))#{reason => <<"multiple module declarations prevent unique source identity">>},
            {null, line(First), [Error]}
    end,
    #{path => unicode:characters_to_binary(Path), module => Module,
        module_line => ModuleLine, findings => Errors ++ Findings}.

%% Read literal attributes, retaining syntax-tree forms elsewhere.
-spec attribute(erl_syntax:syntaxTree()) -> {atom(), term()} | none.
attribute(Form) ->
    case erl_syntax:type(Form) of
        attribute ->
            Name = erl_syntax:atom_value(erl_syntax:attribute_name(Form)),
            case Name of
                Kind when Kind =:= type; Kind =:= opaque ->
                    [Arg] = erl_syntax:attribute_arguments(Form),
                    [TypeName, _Definition, Args] = erl_syntax:tuple_elements(Arg),
                    {Kind, {erl_syntax:atom_value(TypeName), none,
                            lists:duplicate(erl_syntax:list_length(Args), argument)}};
                Kind when Kind =:= spec; Kind =:= callback ->
                    [Arg] = erl_syntax:attribute_arguments(Form),
                    [Key, _Definition] = erl_syntax:tuple_elements(Arg),
                    {Kind, {erl_syntax:concrete(Key), none}};
                compile ->
                    All = erl_syntax_lib:fold(fun(Node, Found) ->
                        Found orelse (erl_syntax:type(Node) =:= atom andalso
                                      erl_syntax:atom_value(Node) =:= export_all)
                    end, false, Form),
                    {compile, case All of true -> export_all; false -> [] end};
                Kind when Kind =:= export; Kind =:= export_type; Kind =:= doc ->
                    {attribute, _, Name, Value} = erl_syntax:revert(Form),
                    {Name, Value};
                _ -> none
            end;
        _ -> none
    end.

%% Collect source-declared exports rather than inferring exports from spelling.
-spec exports([erl_syntax:syntaxTree()], atom()) -> [{atom(), non_neg_integer()}].
exports(Forms, Attribute) ->
    lists:append([Values || F <- Forms, {Name, Values} <- [attribute(F)],
                           Name =:= Attribute, is_list(Values)]).

%% A doc attribute attaches to the next function, type or callback declaration.
-spec inspect([erl_syntax:syntaxTree()], map(), [erl_syntax:syntaxTree()], [finding()]) -> [finding()].
inspect([], _Context, _Pending, Found) -> lists:reverse(Found);
inspect([Form | Rest], Context, Pending, Found) ->
    case {erl_syntax:type(Form), attribute(Form)} of
        {function, _} ->
            Key = {erl_syntax:atom_value(erl_syntax:function_name(Form)),
                   erl_syntax:function_arity(Form)},
            Public = maps:get(all, Context) orelse lists:member(Key, maps:get(exports, Context)),
            New = declaration(function, Key, Public, Form, Pending, Context),
            inspect(Rest, Context, [], lists:reverse(New) ++ Found);
        {attribute, {Kind, {Name, _Definition, Args}}} when Kind =:= type; Kind =:= opaque ->
            Key = {Name, length(Args)},
            New = declaration(type, Key, lists:member(Key, maps:get(types, Context)), Form, Pending, Context),
            inspect(Rest, Context, [], lists:reverse(New) ++ Found);
        {attribute, {doc, _}} -> inspect(Rest, Context, [Form | Pending], Found);
        {attribute, {spec, _}} -> inspect(Rest, Context, [Form | Pending], Found);
        {attribute, {callback, {Key, _}}} ->
            New = declaration(callback, Key, true, Form, Pending, Context),
            inspect(Rest, Context, [], lists:reverse(New) ++ Found);
        {error_marker, _} ->
            %% Record-field-splicing macros are valid after preprocessing but
            %% outside dodger's grammar. Records contain no checked declarations.
            case record_form(line(Form), maps:get(tokens, Context), []) of
                true -> inspect(Rest, Context, [], Found);
                false ->
                    Id = iolist_to_binary(io_lib:format("parse:~B", [line(Form)])),
                    New = diagnostic(Context, Form, Id, <<"parse">>, formatted(Form)),
                    inspect(Rest, Context, [], [New | Found])
            end;
        _ -> inspect(Rest, Context, [], Found)
    end.

%% Check public prose, private explanations, and specs independently.
-spec declaration(function | type | callback, {atom(), non_neg_integer()}, boolean(),
                  erl_syntax:syntaxTree(), [erl_syntax:syntaxTree()], map()) -> [finding()].
declaration(Kind, Key = {Name, Arity}, Public, Form, Pending, Context) ->
    Id = iolist_to_binary(io_lib:format("~s:~s/~B", [Kind, Name, Arity])),
    Specs = maps:get(specs, Context),
    Attached = case maps:find(Key, Specs) of
        {ok, Spec} when Kind =:= function -> [Spec | Pending];
        _ -> Pending
    end,
    Fingerprint = [term_to_binary(Public), fingerprint_form(Form, Context) |
        lists:sort([formatted(A) || A <- lists:usort(Attached)])],
    Doc = lists:any(fun(A) ->
        case attribute(A) of
            {doc, Text} when is_list(Text); is_binary(Text) -> string:trim(Text) =/= "" andalso string:trim(Text) =/= <<>>;
            _ -> false
        end
    end, Pending),
    Comment = lists:any(fun(A) -> preceding_comment(line(A), maps:get(lines, Context)) end,
                        [Form | Pending]),
    Rules = case {Public, Doc, Comment} of
        {true, false, _} -> [<<"public_doc">>];
        {false, false, false} -> [<<"private_comment">>];
        _ -> []
    end,
    Missing = case Kind =:= function andalso not maps:is_key(Key, Specs) of
        true -> [<<"spec">> | Rules];
        false -> Rules
    end,
    Basic = [diagnostic(Context, Form, Id, Rule, Fingerprint) || Rule <- Missing],
    Basic ++ clause_comments(Kind, Name, Form, Id, Fingerprint, Context).

%% Dispatch callbacks warrant a description of each separately serviced message.
-spec clause_comments(function | type | callback, atom(), erl_syntax:syntaxTree(), binary(), iodata(), map()) -> [finding()].
clause_comments(function, Name, Form, Id, Fingerprint, Context)
        when Name =:= handle_call; Name =:= handle_cast; Name =:= handle_info; Name =:= handle_event ->
    case erl_syntax:function_clauses(Form) of
        [_] -> [];
        Clauses -> [diagnostic(Context, Clause,
                    <<Id/binary, ":clause:", (integer_to_binary(Index))/binary>>,
                    <<"clause_comment">>, Fingerprint)
                    || {Index, Clause} <- lists:enumerate(Clauses),
                       not preceding_comment(line(Clause), maps:get(lines, Context))]
    end;
clause_comments(_Kind, _Name, _Form, _Id, _Fingerprint, _Context) -> [].

%% Only an adjacent nonempty comment block explains the declaration below it.
-spec preceding_comment(integer(), [string()]) -> boolean().
preceding_comment(Line, Lines) ->
    comment_lines(lists:reverse(lists:sublist(Lines, max(0, Line - 1)))).

%% Ignore whitespace and decorative separators, but never scan across source code.
-spec comment_lines([string()]) -> boolean().
comment_lines([]) -> false;
comment_lines([Text | Rest]) ->
    case string:trim(Text) of
        [] -> comment_lines(Rest);
        [$% | Comment] ->
            case string:trim(string:trim(Comment, leading, "%")) of
                [] -> comment_lines(Rest);
                _ -> true
            end;
        _ -> false
    end.

%% Render independently of original line numbers and incidental whitespace.
-spec formatted(erl_syntax:syntaxTree()) -> binary().
formatted(Form) -> unicode:characters_to_binary(erl_prettypr:format(Form)).

%% Syntax tools may carry either line or line/column annotations.
-spec line(erl_syntax:syntaxTree()) -> integer().
line(Form) -> erl_anno:line(erl_syntax:get_pos(Form)).

%% Add the declaration's source location to its stable identity and digest.
-spec diagnostic(map(), erl_syntax:syntaxTree(), binary(), binary(), iodata()) -> finding().
diagnostic(#{path := Path}, Form, Id, Rule, Fingerprint) ->
    finding(Path, line(Form), Id, Rule, Fingerprint).

%% A changed body or spec cannot inherit an untouched declaration's exemption.
-spec finding(string(), integer(), binary(), binary(), iodata()) -> finding().
finding(Path, Line, Id, Rule, Content) ->
    #{path => unicode:characters_to_binary(Path), line => Line, id => Id,
      rule => Rule, fingerprint => binary:encode_hex(crypto:hash(sha256, Content), lowercase)}.

%% Identify the lexical form enclosing an error; never skip function or type errors.
-spec record_form(integer(), [erl_scan:token()], [erl_scan:token()]) -> boolean().
record_form(_Line, [], _Acc) -> false;
record_form(Line, [{dot, Anno} | Rest], Acc) ->
    case erl_anno:line(Anno) >= Line of
        true ->
            case lists:reverse(Acc) of
                [{'-', _}, {atom, _, record} | _] -> true;
                _ -> false
            end;
        false -> record_form(Line, Rest, [])
    end;
record_form(Line, [Token | Rest], Acc) -> record_form(Line, Rest, [Token | Acc]).

%% Guarded assertion macro arguments are legal after expansion but not ordinary
%% expressions. Recover only function structure; retain raw tokens for its digest.
-spec recover_macros(string(), [erl_syntax:syntaxTree()], [erl_scan:token()]) ->
    {[erl_syntax:syntaxTree()], [integer()]}.
recover_macros(Path, Forms, Tokens) ->
    case lists:any(fun(F) -> erl_syntax:type(F) =:= error_marker end, Forms) of
        false -> {Forms, []};
        true ->
            {ok, Quick} = epp_dodger:quick_parse_file(Path, [{no_fail, false}]),
            Functions = maps:from_list([{line(F), F} || F <- Quick,
                erl_syntax:type(F) =:= function]),
            lists:mapfoldl(fun(Form, RawLines) ->
                case erl_syntax:type(Form) of
                    error_marker ->
                        [First | _] = source_tokens(line(Form), Tokens, []),
                        Start = erl_anno:line(element(2, First)),
                        case maps:find(Start, Functions) of
                            {ok, Function} -> {Function, [Start | RawLines]};
                            error -> {Form, RawLines}
                        end;
                    _ -> {Form, RawLines}
                end
            end, [], Forms)
    end.

%% Never lose macro argument changes when only the outer declaration parsed.
-spec fingerprint_form(erl_syntax:syntaxTree(), map()) -> binary().
fingerprint_form(Form, #{raw_lines := RawLines, tokens := Tokens}) ->
    case lists:member(line(Form), RawLines) of
        true -> term_to_binary([setelement(2, Token, 0)
            || Token <- source_tokens(line(Form), Tokens, [])]);
        false -> formatted(Form)
    end.

%% Find one complete lexical form without executing preprocessing directives.
-spec source_tokens(integer(), [erl_scan:token()], [erl_scan:token()]) -> [erl_scan:token()].
source_tokens(_Line, [], Acc) -> lists:reverse(Acc);
source_tokens(Line, [{dot, Anno} = Token | Rest], Acc) ->
    case erl_anno:line(Anno) >= Line of
        true -> lists:reverse([Token | Acc]);
        false -> source_tokens(Line, Rest, [])
    end;
source_tokens(Line, [Token | Rest], Acc) -> source_tokens(Line, Rest, [Token | Acc]).
