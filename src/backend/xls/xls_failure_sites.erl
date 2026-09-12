-module(xls_failure_sites).
-moduledoc "Compact failure codes and source maps shared by lowering and debug bindings.".
-export([prepare/1, at/2, emit/2, generic/0, validate/1]).

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
    case length(Origins) =< 4095 of
        true -> ok;
        false -> error({failure_site_capacity, length(Origins), 4095})
    end,
    Source = [begin
        {Reason, Kind} = lists:keyfind(Kind, 2, generic()),
        #{code => (Site bsl 4) bor Reason, kind => Kind, file => list_to_binary(File), line => Line}
    end || {Site, {File, Line, Kind}} <- lists:enumerate(Origins)],
    {Annotated, Source}.

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

%% The source inventory also covers CPU-only functions, irrefutable patterns,
%% and exhaustive branches. Only declare symbols surviving callback lowering;
%% keep their allocated codes unchanged, independent of renderer simplifications.
emit(Sites, Body) ->
    Used = case re:run(iolist_to_binary(Body),
            "\\bXLS_FAILURE_SITE_[A-Z_]+_[0-9A-F]{8}_L[0-9]+\\b",
            [global, {capture, first, binary}]) of
        {match, Matches} -> maps:from_keys([Name || [Name] <- Matches], true);
        nomatch -> #{}
    end,
    Declarations = [["const ", Name, " = u16:",
        integer_to_list(Code), "; // ", binary_to_list(File), ":L", integer_to_list(Line), "\n"]
        || #{code := Code, file := File, line := Line, kind := Kind} <- Sites,
           Name <- [constant({binary_to_list(File), Line, Kind})],
           is_map_key(iolist_to_binary(Name), Used)],
    [Declarations, Body].

relative(Base, File) -> relative_parts(filename:split(Base), filename:split(File)).
relative_parts([Same | Base], [Same | File]) -> relative_parts(Base, File);
relative_parts(Base, File) -> filename:join(lists:duplicate(length(Base), "..") ++ File).

%% Validate embedded BEAM metadata before it participates in a debug binding.
validate(Sites) when is_list(Sites) ->
    Codes = [validate_site(Site) || Site <- Sites],
    case length(Codes) =:= length(lists:usort(Codes)) of
        true -> ok;
        false -> error(duplicate_failure_code)
    end.

validate_site(#{code := Code, kind := Kind, file := File, line := Line})
        when is_integer(Code), Code >= 16, Code =< 65535,
             is_binary(File), byte_size(File) > 0, is_integer(Line), Line > 0 ->
    case lists:keyfind(Code band 15, 1, generic()) of
        {_, Kind} -> Code;
        _ -> error({failure_code_kind, Code, Kind})
    end;
validate_site(Site) -> error({failure_site, Site}).
