-module(xls_failure_sites).
-moduledoc "Compact failure codes and source maps shared by lowering and debug bindings.".
-export([prepare/1, at/2, emit/2, allocate/2, from_artifact/2, number/1, generic/0, validate_origins/1]).

%% Codes 1..15 describe failures without a source location; zero is success.
%% The low four bits retain the reason; the upper twelve identify a source
%% site. Generated constant names depend
%% only on their origin. Lowerers can reference them without mutable counters
%% or a source-map parameter threaded through every expression operation.
generic() ->
    [{1, function_clause}, {2, match_failure}, {3, request_length},
        {4, case_clause}, {5, if_clause}, {6, explicit_fail},
        {7, invalid_message}, {8, invalid_repeat}, {9, reduction_mismatch},
        {10, reduction_protocol}, {11, invalid_effect}, {12, internal}].

%% epp emits integer line annotations and file attributes at include boundaries.
%% Attach that enclosing file once; lowering then preserves the source origin
%% through synthetic matches, branch joins, and helper calls.
prepare(Forms = [{attribute, _, file, {Main, _}} | _]) ->
    Base = filename:dirname(filename:absname(Main)),
    {Annotated, _} = lists:mapfoldl(fun
        (F = {attribute, _, file, {File, _}}, _) -> {F, relative(Base, filename:absname(File))};
        (F = {function, _, _, _, _}, File) ->
            {erl_parse:map_anno(fun(A) -> erl_anno:set_file(File, A) end, F), File};
        (F, File) -> {F, File}
    end, filename:basename(Main), Forms),
    Origins = lists:usort(lists:append([sites(F) || F = {function, _, _, _, _} <- Annotated])),
    Names = [iolist_to_binary(constant(Origin)) || Origin <- Origins],
    true = length(Names) =:= length(lists:usort(Names)),
    {Annotated, [#{kind => Kind, file => list_to_binary(File), line => Line}
        || {File, Line, Kind} <- Origins]}.

sites({match, _, Pattern, Value}) -> pattern_sites(Pattern) ++ sites(Value);
sites({'case', Line, Subject, Clauses}) -> [origin(case_clause, Line) | sites([Subject, Clauses])];
sites({'if', Line, Clauses}) -> [origin(if_clause, Line) | sites(Clauses)];
sites({clause, Line, Patterns, Guards, Body}) ->
    [origin(function_clause, Line) | pattern_sites(Patterns) ++ sites([Guards, Body])];
sites({tuple, Line, [A, B, C]}) -> [origin(explicit_fail, Line) | sites([A, B, C])];
sites(Tuple) when is_tuple(Tuple) -> sites(tuple_to_list(Tuple));
sites(List) when is_list(List) -> lists:append([sites(X) || X <- List]);
sites(_) -> [].

pattern_sites({Tag, Line, _}) when Tag =:= var; Tag =:= atom; Tag =:= integer ->
    [origin(match_failure, Line)];
pattern_sites(Tuple) when is_tuple(Tuple) -> pattern_sites(tuple_to_list(Tuple));
pattern_sites(List) when is_list(List) -> lists:append([pattern_sites(X) || X <- List]);
pattern_sites(_) -> [].

origin(Kind, Anno) -> {erl_anno:file(Anno), erl_anno:line(Anno), Kind}.

at(Kind, Anno) ->
    case {erl_anno:file(Anno), erl_anno:line(Anno)} of
        {undefined, _} -> generic_code(Kind);
        {_, 0} -> generic_code(Kind);
        {File, Line} -> constant({File, Line, Kind})
    end.

generic_code(Kind) ->
    {_Code, Kind} = lists:keyfind(Kind, 2, generic()),
    ["hls_failure::", string:uppercase(atom_to_list(Kind))].

constant({File, Line, Kind}) ->
    <<Prefix:4/binary, _/binary>> = crypto:hash(sha256, File),
    Hash = binary_to_list(binary:encode_hex(Prefix)),
    ["XLS_FAILURE_SITE_", string:uppercase(atom_to_list(Kind)), "_", Hash,
        "_L", integer_to_list(Line)].

%% Allocate only after lowering has eliminated unused candidates. The same
%% artifact text supplies both declarations and the debug projection's codebook.
allocate(Origins, Body) ->
    Used = case re:run(iolist_to_binary(Body),
            "\\bXLS_FAILURE_SITE_[A-Z_]+_[0-9A-F]{8}_L[0-9]+\\b",
            [global, {capture, first, binary}]) of
        {match, Matches} -> maps:from_keys([Name || [Name] <- Matches], true);
        nomatch -> #{}
    end,
    Selected = [Origin || Origin = #{file := File, line := Line, kind := Kind} <- Origins,
        is_map_key(iolist_to_binary(constant({binary_to_list(File), Line, Kind})), Used)],
    %% Fail at this boundary if a lowerer creates a symbol absent from the
    %% inventory, rather than emitting a dangling reference or partial codebook.
    case length(Selected) =:= map_size(Used) of
        true -> number(Selected);
        false -> error({unknown_failure_sites, maps:keys(Used) --
            [iolist_to_binary(constant({binary_to_list(F), L, K}))
                || #{file := F, line := L, kind := K} <- Selected]})
    end.

%% Verify the numeric declarations as well as the symbolic references. This
%% rejects a stale or hand-edited artifact before it can label debug responses.
from_artifact(Origins, Dslx) ->
    Sites = allocate(Origins, Dslx),
    Actual = case re:run(iolist_to_binary(Dslx),
            "^const (XLS_FAILURE_SITE_[A-Z_]+_[0-9A-F]{8}_L[0-9]+) = u16:([0-9]+);",
            [global, multiline, {capture, [1, 2], binary}]) of
        {match, Matches} -> lists:sort(Matches);
        nomatch -> []
    end,
    Expected = lists:sort([[iolist_to_binary(constant({binary_to_list(F), L, K})),
        integer_to_binary(C)] || #{file := F, line := L, kind := K, code := C} <- Sites]),
    case Actual =:= Expected of
        true -> Sites;
        false -> error(failure_codebook_mismatch)
    end.

number(Origins) ->
    Ordered = lists:sort([{F, L, K} || #{file := F, line := L, kind := K} <- Origins]),
    case length(Ordered) =< 4095 of
        true -> ok;
        false -> error({failure_site_capacity, length(Ordered), 4095})
    end,
    [begin
        {Reason, Kind} = lists:keyfind(Kind, 2, generic()),
        #{code => (Index bsl 4) bor Reason, kind => Kind, file => File, line => Line}
    end || {Index, {File, Line, Kind}} <- lists:enumerate(Ordered)].

emit(Origins, Body) ->
    Declarations = [["const ", constant({binary_to_list(File), Line, Kind}), " = u16:",
        integer_to_list(Code), "; // ", binary_to_list(File), ":L", integer_to_list(Line), "\n"]
        || #{code := Code, file := File, line := Line, kind := Kind} <- allocate(Origins, Body)],
    [Declarations, Body].

relative(Base, File) -> relative_parts(filename:split(Base), filename:split(File)).
relative_parts([Same | Base], [Same | File]) -> relative_parts(Base, File);
relative_parts(Base, File) -> filename:join(lists:duplicate(length(Base), "..") ++ File).

%% This structural inventory is embedded while compiling BEAM, before type
%% providers are necessarily available. It carries no hardware code allocation.
validate_origins(Origins) when is_list(Origins) ->
    lists:foreach(fun validate_origin/1, Origins),
    case length(Origins) =:= length(lists:usort(Origins)) of
        true -> ok;
        false -> error(duplicate_failure_origin)
    end.

validate_origin(#{kind := Kind, file := File, line := Line} = Origin)
        when map_size(Origin) =:= 3, is_binary(File), byte_size(File) > 0,
             is_integer(Line), Line > 0 ->
    case lists:keymember(Kind, 2, generic()) of
        true -> ok;
        false -> error({failure_kind, Kind})
    end;
validate_origin(Origin) -> error({failure_origin, Origin}).
