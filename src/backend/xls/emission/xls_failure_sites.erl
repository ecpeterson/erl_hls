-module(xls_failure_sites).
-moduledoc "Connects selected source locations to structured failure references created by lowerers and providers. xls_emitted allocates only references retained in the final document; debug catalog validation checks those sites against independently collected locations. Printed provider text never creates source metadata, and generic synthetic failures remain distinct from source sites.".
%% Collect source locations and attach failures during lowering.
-export([prepare/1, at/2, generic/0]).
%% Allocate the final document and render its codebook symbols.
-export([allocate/2, number/1, reference/1, declarations/1]).
%% Validate retained source locations and external debug catalogs.
-export([validate_locations/1, validate_sites/2, from_catalog/2]).
-export_type([location/0, origin/0, site/0, kind/0]).

-doc "A source position relative to the actor's source directory, including include-file positions.".
-type location() :: #{file := binary(), line := pos_integer()}.
-doc "The finite hardware failure reasons; code zero remains success.".
-type kind() ::
    function_clause
    | match_failure
    | request_length
    | case_clause
    | if_clause
    | explicit_fail
    | invalid_message
    | invalid_repeat
    | reduction_mismatch
    | reduction_protocol
    | invalid_effect
    | internal
    | badarith
    | badarg
    | reply_contract.
-doc "A failure selected by lowering at an annotated source position.".
-type origin() :: #{file := binary(), line := pos_integer(), kind := kind()}.
-doc "An emitted failure origin with its artifact-local 16-bit code.".
-type site() :: #{
    file := binary(), line := pos_integer(), kind := kind(), code := 16..((1 bsl 16) - 1)
}.

-doc "Returns reserved failure kinds which have no individual source site.".
-spec generic() -> [{1..15, kind()}].
generic() ->
    [
        {1, function_clause},
        {2, match_failure},
        {3, request_length},
        {4, case_clause},
        {5, if_clause},
        {6, explicit_fail},
        {7, invalid_message},
        {8, invalid_repeat},
        {9, reduction_mismatch},
        {10, reduction_protocol},
        {11, invalid_effect},
        {12, internal},
        {13, badarith},
        {14, badarg},
        {15, reply_contract}
    ].

-doc "Annotates source functions with relative filenames and inventories their syntax positions. Does not predict failure kinds or invoke providers; safe during BEAM interface extraction.".
-spec prepare([hls_source:form()]) -> {[hls_source:form()], [location()]}.
prepare(Forms = [{attribute, _, file, {Main, _}} | _]) ->
    Base = filename:dirname(filename:absname(Main)),
    {Annotated, _} = lists:mapfoldl(
        fun
            (F = {attribute, _, file, {File, _}}, _) ->
                {F, relative(Base, filename:absname(File))};
            (F = {function, _, _, _, _}, File) ->
                {erl_parse:map_anno(fun(A) -> erl_anno:set_file(File, A) end, F), File};
            (F, File) ->
                {F, File}
        end,
        filename:basename(Main),
        Forms
    ),
    Locations = lists:usort(
        lists:append([
            erl_parse:fold_anno(fun collect_location/2, [], F)
         || F = {function, _, _, _, _} <- Annotated
        ])
    ),
    {Annotated, Locations}.

%% Ignore synthetic position zero; it uses a reserved generic code.
-spec collect_location(erl_anno:anno(), [location()]) -> [location()].
collect_location(Anno, Acc) ->
    case {erl_anno:file(Anno), erl_anno:line(Anno)} of
        {undefined, _} -> Acc;
        {_, 0} -> Acc;
        {File, Line} -> [#{file => unicode:characters_to_binary(File), line => Line} | Acc]
    end.

-doc "Builds a structured failure reference; unlocated synthetic operations use a reserved generic code.".
-spec at(kind(), erl_anno:anno()) -> xls_dslx:value().
at(Kind, Anno) ->
    case {erl_anno:file(Anno), erl_anno:line(Anno)} of
        {undefined, _} ->
            generic_code(Kind);
        {_, 0} ->
            generic_code(Kind);
        {File, Line} ->
            xls_dslx:failure_ref(#{
                file => unicode:characters_to_binary(File),
                line => Line,
                kind => Kind
            })
    end.

%% Keep the reason in the runtime module for failures without source metadata.
-spec generic_code(kind()) -> iodata().
generic_code(Kind) ->
    {_Code, Kind} = lists:keyfind(Kind, 2, generic()),
    ["hls_failure::", string:uppercase(atom_to_list(Kind))].

-doc "Renders the stable symbol for one checked origin. This terminal renderer does not allocate a code.".
-spec reference(origin() | site()) -> iodata().
reference(#{file := File, line := Line, kind := Kind}) ->
    <<Prefix:4/binary, _/binary>> = crypto:hash(sha256, File),
    [
        "XLS_FAILURE_SITE_",
        string:uppercase(atom_to_list(Kind)),
        "_",
        binary:encode_hex(Prefix),
        "_L",
        integer_to_list(Line)
    ].

-doc "Numbers only structured failure references retained in the final module document. Plain text never introduces metadata; unknown source positions and symbol collisions reject.".
-spec allocate([location()], xls_dslx:value()) -> [site()].
allocate(Locations, Document) ->
    ok = xls_dslx:validate(Document),
    Origins = lists:usort(references(Document)),
    Sites = number(Origins),
    ok = validate_sites(Locations, Sites),
    Names = [iolist_to_binary(reference(Origin)) || Origin <- Origins],
    case length(Names) =:= length(lists:usort(Names)) of
        true -> Sites;
        false -> error(failure_symbol_collision)
    end.

%% Traverse nodes, never printed spelling. Validated leaf values contain no refs.
-spec references(term()) -> [origin()].
references({xls_dslx, failure_ref, Origin}) -> [Origin];
references(Tuple) when is_tuple(Tuple) -> references(tuple_to_list(Tuple));
references(List) when is_list(List) -> lists:append([references(X) || X <- List]);
references(_) -> [].

-doc "Assigns deterministic codes to distinct origins, ordered by file, line and kind; rejects more than 4095 sites.".
-spec number([origin()]) -> [site()].
number(Origins) ->
    lists:foreach(fun validate_origin/1, Origins),
    case length(Origins) =:= length(lists:usort(Origins)) of
        true -> ok;
        false -> error(duplicate_failure_origin)
    end,
    Ordered = lists:sort([{F, L, K} || #{file := F, line := L, kind := K} <- Origins]),
    case length(Ordered) =< 4095 of
        true -> ok;
        false -> error({failure_site_capacity, length(Ordered), 4095})
    end,
    [
        begin
            {Reason, Kind} = lists:keyfind(Kind, 2, generic()),
            #{code => (Index bsl 4) bor Reason, kind => Kind, file => File, line => Line}
        end
     || {Index, {File, Line, Kind}} <- lists:enumerate(Ordered)
    ].

-doc "Renders declarations for an allocated codebook; callers must bind it to the same final document.".
-spec declarations([site()]) -> iodata().
declarations(Sites) ->
    [
        [
            "const ",
            reference(Site),
            " = u16:",
            integer_to_list(Code),
            "; // ",
            File,
            ":L",
            integer_to_list(Line),
            "\n"
        ]
     || Site = #{code := Code, file := File, line := Line} <- Sites
    ].

-doc "Checks a BEAM syntax-position inventory without evaluating providers or allocating hardware codes.".
-spec validate_locations([location()]) -> ok.
validate_locations(Locations) when is_list(Locations) ->
    lists:foreach(fun validate_location/1, Locations),
    case length(Locations) =:= length(lists:usort(Locations)) of
        true -> ok;
        false -> error(duplicate_failure_location)
    end.

%% Imported metadata is an untyped boundary despite the checked internal type.
-spec validate_location(location()) -> ok.
validate_location(#{file := File, line := Line} = Location) when
    map_size(Location) =:= 2,
    is_binary(File),
    byte_size(File) > 0,
    is_integer(Line),
    Line > 0
->
    ok;
validate_location(Location) ->
    error({failure_location, Location}).

%% A lowerer may introduce any supported kind, but cannot invent a source position.
-spec validate_origin(origin()) -> ok.
validate_origin(#{kind := Kind} = Origin) when map_size(Origin) =:= 3 ->
    ok = validate_location(maps:remove(kind, Origin)),
    case lists:keymember(Kind, 2, generic()) of
        true -> ok;
        false -> error({failure_kind, Kind})
    end;
validate_origin(Origin) ->
    error({failure_origin, Origin}).

-doc "Validates canonical numbering and origin membership against an independently obtained source inventory.".
-spec validate_sites([location()], [site()]) -> ok.
validate_sites(Locations, Sites) ->
    ok = validate_locations(Locations),
    Known = maps:from_keys(Locations, true),
    Origins = [maps:remove(code, S) || S <- Sites],
    case number(Origins) =:= Sites of
        true -> ok;
        false -> error(failure_codebook_mismatch)
    end,
    case [O || O <- Origins, not is_map_key(maps:without([kind], O), Known)] of
        [] -> ok;
        Unknown -> error({unknown_failure_sites, Unknown})
    end.

-doc "Checks a JSON debug catalog, including generic codes, against source positions and canonical allocation. This checks consistency, not the authenticity of an externally replaced artifact.".
-spec from_catalog([location()], #{binary() => map()}) -> [site()].
from_catalog(Locations, Catalog) ->
    Sites = [
        catalog_site(Code, Value)
     || {Code, Value} <- maps:to_list(Catalog),
        not lists:member(Code, [integer_to_binary(C) || {C, _} <- generic()])
    ],
    Ordered = lists:sort(fun(#{code := A}, #{code := B}) -> A < B end, Sites),
    ok = validate_sites(Locations, Ordered),
    Expected = maps:from_list(
        [
            {integer_to_binary(C), #{<<"kind">> => atom_to_binary(K)}}
         || {C, K} <- generic()
        ] ++
            [
                {integer_to_binary(C), #{
                    <<"kind">> => atom_to_binary(K), <<"file">> => F, <<"line">> => L
                }}
             || #{code := C, kind := K, file := F, line := L} <- Ordered
            ]
    ),
    case Expected =:= Catalog of
        true -> Ordered;
        false -> error(failure_codebook_mismatch)
    end.

%% Use a finite lookup rather than interning untrusted catalog kind strings.
-spec catalog_site(binary(), map()) -> site().
catalog_site(Code, #{<<"kind">> := Kind, <<"file">> := File, <<"line">> := Line} = Value) when
    map_size(Value) =:= 3
->
    case [K || {_, K} <- generic(), atom_to_binary(K) =:= Kind] of
        [K] -> #{code => binary_to_integer(Code), kind => K, file => File, line => Line};
        [] -> error({failure_kind, Kind})
    end;
catalog_site(_, _) ->
    error(failure_codebook_mismatch).

%% Source maps use relocatable paths anchored at the main module's directory.
-spec relative(file:filename(), file:filename()) -> file:filename().
relative(Base, File) -> relative_parts(filename:split(Base), filename:split(File)).

%% Remove the common path prefix before emitting any parent-directory components.
-spec relative_parts([file:filename()], [file:filename()]) -> file:filename().
relative_parts([Same | Base], [Same | File]) -> relative_parts(Base, File);
relative_parts(Base, File) -> filename:join(lists:duplicate(length(Base), "..") ++ File).
