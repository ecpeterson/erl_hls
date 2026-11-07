-module(hls_spacetime_sdf).
-include_lib("kernel/include/file.hrl").
-moduledoc "Bounded reader for native SDF sidecars used by spacetime import. Preserves token spelling and every balanced form, including conditions, transitions, timing checks and unknown extensions. It checks DELAYFILE/cell metadata and timescale shape, not the complete SDF language, numerical timing semantics or dynamic causality.".

%% Offline native-sidecar boundary; never invokes a vendor tool.
-export([read/2, validate/1, describe/1, validate_description/1]).
%% Serialized forms contain only maps, lists, binaries and fixed enum atoms.
-export_type([options/0, form/0, parsed/0, description/0]).

-define(MAX_BYTES, 268435456).
-define(MAX_NODES, 8000000).
-define(MAX_DEPTH, 128).
-define(MAX_TOKEN, 1048576).

-doc "Expected sidecar digest and separately declared write_sdf provenance. The selected process corner is distinct from min/typ/max fields inside SDF values; neither is inferred from the filename.".
-type options() :: #{sha256 := binary(), corner := fast | slow, mode := sta}.

-doc "One S-expression list or lexical token. A string lexeme includes its original quotes and escapes; a symbol lexeme retains SDF escapes. No external spelling becomes an Erlang atom. Comments/whitespace remain in the authoritative raw sidecar, not this tree.".
-type form() :: #{kind := symbol | string, lexeme := binary()} | [form()].

%% Cell forms occur once; metadata strips surrounding quotes only, retaining SDF name escapes.
-type cell() :: #{celltype := binary(), instance := binary(), form := form()}.
%% The magnitude is an exact decimal spelling; this reader performs no physical-unit conversion.
-type timescale() :: #{magnitude := binary(), unit := fs | ps | ns | us | ms | s}.

-doc "A digest-bound SDF document with preserved headers and one full form per cell. Empty instance denotes the top cell. Metadata retains SDF escape spelling and does not assert native-catalogue identity. Counts include the DELAYFILE root/head; unknown forms are retained without interpretation.".
-type parsed() :: #{
    source := #{
        sha256 := binary(),
        bytes := non_neg_integer(),
        corner := fast | slow,
        mode := sta
    },
    headers := [form()],
    timescale := timescale(),
    cells := [cell()],
    counts := #{cells := non_neg_integer(), nodes := pos_integer()}
}.

-doc "Compact reference to a separately retained complete SDF sidecar. The population digest hashes sorted [instance,celltype] JSON rows with SDF escape spelling preserved; it is not a native-catalogue correspondence proof. An importer may attach its relative filename as file. Reopen the sidecar to inspect its full forms.".
-type description() :: #{
    file => binary(),
    source := #{
        sha256 := binary(),
        bytes := non_neg_integer(),
        corner := fast | slow,
        mode := sta
    },
    timescale := timescale(),
    counts := #{cells := non_neg_integer(), nodes := pos_integer()},
    instance_population_sha256 := binary()
}.

-doc "Reads at most 256 MiB from a regular file and verifies its exact SHA256. Bounds the tree at eight million nodes, depth 128 and one MiB per token; preserves all forms without classifying delay values. Raises {spacetime_sdf, Reason} for rejected data and file errors.".
-spec read(file:filename_all(), options()) -> parsed().
read(Path, Options) ->
    ok = options(Options),
    Info =
        case file:read_file_info(Path) of
            {ok, I} -> I;
            {error, Reason} -> fail({file, Reason})
        end,
    require(Info#file_info.type =:= regular andalso Info#file_info.size =< ?MAX_BYTES, file_limit),
    Bytes =
        case file:read_file(Path) of
            {ok, B} -> B;
            {error, Error} -> fail({read, Error})
        end,
    require(byte_size(Bytes) =:= Info#file_info.size, changed_size),
    require(unicode:characters_to_binary(Bytes) =:= Bytes, utf8),
    Digest = binary:encode_hex(crypto:hash(sha256, Bytes), lowercase),
    require(Digest =:= maps:get(sha256, Options), digest_mismatch),
    {Root, Rest, Nodes} = value(skip(Bytes), 0, 0),
    require(skip(Rest) =:= <<>>, trailing_forms),
    {Headers, Cells} = document(Root),
    Result = #{
        source => Options#{bytes => byte_size(Bytes)},
        headers => Headers,
        timescale => timescale(Headers),
        cells => Cells,
        counts => #{cells => length(Cells), nodes => Nodes}
    },
    ok = validate(Result),
    Result.

-doc "Checks serialized provenance, bounded form structure, counts and derived cell/timescale metadata. It does not reauthenticate the unavailable raw bytes, interpret numeric delay slots, or resolve SDF names into native pins. Raises {spacetime_sdf, Reason}.".
-spec validate(parsed()) -> ok.
validate(#{
    source := Source = #{bytes := Bytes},
    headers := Headers,
    timescale := Scale,
    cells := Cells,
    counts := #{cells := CellCount, nodes := NodeCount}
}) ->
    ok = options(Source),
    require(is_integer(Bytes) andalso Bytes >= 0 andalso Bytes =< ?MAX_BYTES, source_bytes),
    require(is_list(Headers) andalso is_list(Cells), document_tables),
    require(CellCount =:= length(Cells), cell_count),
    HeaderNodes = nodes(Headers, 1, 2),
    require(lists:all(fun(Form) -> tag(Form) =/= <<"CELL">> end, Headers), header_cell),
    require(Scale =:= timescale(Headers), timescale_mismatch),
    Count = lists:foldl(
        fun
            (Cell = #{form := Form}, Acc) ->
                Next = checked_node(Form, 1, Acc),
                require(Cell =:= cell(Form), cell_metadata),
                Next;
            (_, _) ->
                fail(cell_shape)
        end,
        HeaderNodes,
        Cells
    ),
    require(NodeCount =:= Count, node_count),
    ok;
validate(_) ->
    fail(document_shape).

-doc "Validates a parsed sidecar and returns compact provenance, bounds, timescale and instance-population identity without copying its full tree into another artifact.".
-spec describe(parsed()) -> description().
describe(Parsed = #{source := Source, timescale := Scale, cells := Cells, counts := Counts}) ->
    ok = validate(Parsed),
    Population = lists:sort([[maps:get(instance, C), maps:get(celltype, C)] || C <- Cells]),
    Digest = binary:encode_hex(crypto:hash(sha256, json:encode(Population)), lowercase),
    #{source => Source, timescale => Scale, counts => Counts, instance_population_sha256 => Digest}.

-doc "Checks compact descriptor shape, bounded counts, declared provenance and digest syntax. The sidecar bytes and native identity correspondence must be verified separately; this descriptor alone cannot establish either.".
-spec validate_description(description()) -> ok.
validate_description(#{
    source := Source = #{bytes := Bytes},
    timescale := Scale,
    counts := #{cells := Cells, nodes := Nodes},
    instance_population_sha256 := Digest
}) ->
    ok = options(Source),
    require(is_integer(Bytes) andalso Bytes >= 0 andalso Bytes =< ?MAX_BYTES, source_bytes),
    require(
        is_integer(Cells) andalso Cells >= 0 andalso is_integer(Nodes) andalso
            Nodes >= 2 andalso Nodes =< ?MAX_NODES andalso Cells =< Nodes,
        counts
    ),
    require(
        is_binary(Digest) andalso byte_size(Digest) =:= 64 andalso
            re:run(Digest, <<"^[0-9a-f]{64}$">>, [{capture, none}]) =:= match,
        population_digest
    ),
    #{magnitude := Magnitude, unit := Unit} = Scale,
    require(is_binary(Magnitude) andalso lists:member(Unit, [fs, ps, ns, us, ms, s]), timescale),
    Form = [
        #{kind => symbol, lexeme => <<"TIMESCALE">>},
        #{kind => symbol, lexeme => <<Magnitude/binary, (atom_to_binary(Unit))/binary>>}
    ],
    require(Scale =:= timescale([Form]), timescale_mismatch),
    ok;
validate_description(_) ->
    fail(description_shape).

%% Provenance uses fixed vocabulary and an explicit digest, not a guessed process corner.
-spec options(map()) -> ok.
options(#{sha256 := Digest, corner := Corner, mode := sta}) ->
    require(is_binary(Digest) andalso byte_size(Digest) =:= 64, digest_shape),
    require(re:run(Digest, <<"^[0-9a-f]{64}$">>, [{capture, none}]) =:= match, digest_shape),
    require(Corner =:= fast orelse Corner =:= slow, process_corner);
options(_) ->
    fail(provenance).

%% Only the outer document and required cell metadata are interpreted; other forms stay intact.
-spec document(form()) -> {[form()], [cell()]}.
document([#{kind := symbol, lexeme := <<"DELAYFILE">>} | Forms]) ->
    {Headers, Cells} = lists:foldl(
        fun(Form, {Hs, Cs}) ->
            case tag(Form) of
                <<"CELL">> -> {Hs, [cell(Form) | Cs]};
                _ -> {[Form | Hs], Cs}
            end
        end,
        {[], []},
        Forms
    ),
    {lists:reverse(Headers), lists:reverse(Cells)};
document(_) ->
    fail(delayfile).

%% Standard metadata names are retained with their SDF escape spelling, not silently normalized.
-spec cell(form()) -> cell().
cell(Form = [#{kind := symbol, lexeme := <<"CELL">>} | Children]) ->
    Type =
        case named(<<"CELLTYPE">>, Children) of
            [_, Token] -> name(Token);
            _ -> fail(celltype)
        end,
    require(byte_size(Type) > 0, celltype),
    Instance =
        case named(<<"INSTANCE">>, Children) of
            [_] -> <<>>;
            [_, Token2] -> name(Token2);
            _ -> fail(instance)
        end,
    #{celltype => Type, instance => Instance, form => Form};
cell(_) ->
    fail(cell_shape).

%% Exactly one required metadata form prevents conflicting interpretations of one document/cell.
-spec named(binary(), [form()]) -> form().
named(Name, Forms) ->
    case [F || F <- Forms, tag(F) =:= Name] of
        [Form] -> Form;
        _ -> fail({metadata, Name})
    end.

%% Unknown head symbols are ordinary preserved forms, not discarded extensions.
-spec tag(form()) -> binary() | undefined.
tag([#{kind := symbol, lexeme := Name} | _]) -> Name;
tag(_) -> undefined.

%% Quotation is removed for display metadata only; the full lexeme stays in its original form.
-spec name(form()) -> binary().
name(#{kind := symbol, lexeme := Lexeme}) ->
    Lexeme;
name(#{kind := string, lexeme := Lexeme}) when byte_size(Lexeme) >= 2 ->
    binary:part(Lexeme, 1, byte_size(Lexeme) - 2);
name(_) ->
    fail(name_token).

%% Standard adjacent or whitespace-separated timescale spellings preserve an exact decimal value.
-spec timescale([form()]) -> timescale().
timescale(Headers) ->
    Text =
        case named(<<"TIMESCALE">>, Headers) of
            [_, #{kind := symbol, lexeme := V}] ->
                V;
            [_, #{kind := symbol, lexeme := V}, #{kind := symbol, lexeme := U}] ->
                <<V/binary, U/binary>>;
            _ ->
                fail(timescale)
        end,
    case
        re:run(
            Text,
            <<"^([0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)(fs|ps|ns|us|ms|s)$">>,
            [{capture, [1, 2], binary}]
        )
    of
        {match, [Magnitude, Unit]} ->
            require(re:run(Magnitude, <<"[1-9]">>, [{capture, none}]) =:= match, timescale_zero),
            #{magnitude => Magnitude, unit => unit(Unit)};
        _ ->
            fail(timescale)
    end.

%% Units are fixed vocabulary; no untrusted token is interned.
-spec unit(binary()) -> fs | ps | ns | us | ms | s.
unit(<<"fs">>) -> fs;
unit(<<"ps">>) -> ps;
unit(<<"ns">>) -> ns;
unit(<<"us">>) -> us;
unit(<<"ms">>) -> ms;
unit(<<"s">>) -> s.

%% Parse directly into one bounded tree instead of retaining a second whole token stream.
-spec value(binary(), non_neg_integer(), non_neg_integer()) -> {form(), binary(), pos_integer()}.
value(<<$(, Rest/binary>>, Depth, Count) ->
    require(Depth < ?MAX_DEPTH, depth_limit),
    list(skip(Rest), Depth + 1, increment(Count), []);
value(<<$", Rest/binary>> = Whole, _, Count) ->
    Length = quoted(Rest, 1),
    <<Lexeme:Length/binary, Tail/binary>> = Whole,
    {#{kind => string, lexeme => Lexeme}, Tail, increment(Count)};
value(<<>>, _, _) ->
    fail(unexpected_end);
value(<<$), _/binary>>, _, _) ->
    fail(unexpected_close);
value(Binary, _, Count) ->
    Length = symbol(Binary, 0),
    require(Length > 0, empty_symbol),
    <<Lexeme:Length/binary, Tail/binary>> = Binary,
    {#{kind => symbol, lexeme => Lexeme}, Tail, increment(Count)}.

%% List accumulation is reversed once; missing closing parentheses never produce a partial tree.
-spec list(binary(), pos_integer(), pos_integer(), [form()]) -> {form(), binary(), pos_integer()}.
list(<<$), Rest/binary>>, _, Count, Acc) ->
    {lists:reverse(Acc), Rest, Count};
list(<<>>, _, _, _) ->
    fail(unterminated_list);
list(Binary, Depth, Count, Acc) ->
    {Node, Rest, Next} = value(Binary, Depth, Count),
    list(skip(Rest), Depth, Next, [Node | Acc]).

%% Quoted text retains every escape; only unescaped double quotes terminate the token.
-spec quoted(binary(), pos_integer()) -> pos_integer().
quoted(_, N) when N >= ?MAX_TOKEN -> fail(token_limit);
quoted(<<$", _/binary>>, N) -> N + 1;
quoted(<<$\\, _, Rest/binary>>, N) -> quoted(Rest, N + 2);
quoted(<<_, Rest/binary>>, N) -> quoted(Rest, N + 1);
quoted(<<>>, _) -> fail(unterminated_string).

%% Escaped delimiters remain inside symbols, including escaped brackets and whitespace.
-spec symbol(binary(), non_neg_integer()) -> non_neg_integer().
symbol(_, N) when N > ?MAX_TOKEN -> fail(token_limit);
symbol(<<$\\, _, Rest/binary>>, N) ->
    symbol(Rest, N + 2);
symbol(<<$\\>>, _) ->
    fail(dangling_escape);
symbol(<<C, _/binary>>, N) when
    C =:= $(;
    C =:= $);
    C =:= $";
    C =:= 32;
    C =:= 9;
    C =:= 10;
    C =:= 11;
    C =:= 12;
    C =:= 13
->
    N;
symbol(<<_, Rest/binary>>, N) ->
    symbol(Rest, N + 1);
symbol(<<>>, N) ->
    N.

%% Comments are discarded only at lexical boundaries; raw sidecar hashes preserve their bytes.
-spec skip(binary()) -> binary().
skip(<<C, Rest/binary>>) when C =:= 32; C =:= 9; C =:= 10; C =:= 11; C =:= 12; C =:= 13 ->
    skip(Rest);
skip(<<"//", Rest/binary>>) ->
    skip(line_comment(Rest));
skip(<<"/*", Rest/binary>>) ->
    skip(block_comment(Rest));
skip(Binary) ->
    Binary.

%% A final line comment may end at EOF without hiding a syntactically incomplete document.
-spec line_comment(binary()) -> binary().
line_comment(<<$\n, Rest/binary>>) -> Rest;
line_comment(<<_, Rest/binary>>) -> line_comment(Rest);
line_comment(<<>>) -> <<>>.

%% An unterminated block comment is an incomplete sidecar, even after a closed DELAYFILE.
-spec block_comment(binary()) -> binary().
block_comment(<<"*/", Rest/binary>>) -> Rest;
block_comment(<<_, Rest/binary>>) -> block_comment(Rest);
block_comment(<<>>) -> fail(unterminated_comment).

%% Node accounting applies before allocating another retained tree node.
-spec increment(non_neg_integer()) -> pos_integer().
increment(Count) ->
    require(Count < ?MAX_NODES, node_limit),
    Count + 1.

%% Serialized validation traverses existing trees and recomputes the same bounds without copies.
-spec nodes([form()], non_neg_integer(), non_neg_integer()) -> non_neg_integer().
nodes(Nodes, Depth, Count) ->
    lists:foldl(fun(Node, N) -> checked_node(Node, Depth, N) end, Count, Nodes).

%% Every serialized lexeme must parse as one exact token; numbers and timing arcs remain uninterpreted.
-spec checked_node(form(), non_neg_integer(), non_neg_integer()) -> pos_integer().
checked_node(Node, Depth, Count) when is_list(Node) ->
    require(Depth < ?MAX_DEPTH, depth_limit),
    nodes(Node, Depth + 1, increment(Count));
checked_node(#{kind := Kind, lexeme := Lexeme}, _, Count) ->
    require(
        is_binary(Lexeme) andalso byte_size(Lexeme) > 0 andalso
            byte_size(Lexeme) =< ?MAX_TOKEN andalso unicode:characters_to_binary(Lexeme) =:= Lexeme,
        token
    ),
    require(Kind =:= symbol orelse Kind =:= string, token_kind),
    case value(skip(Lexeme), 0, 0) of
        {#{kind := Kind, lexeme := Lexeme}, <<>>, 1} ->
            increment(Count);
        _ ->
            fail(token_lexeme)
    end;
checked_node(_, _, _) ->
    fail(node).

%% Reader errors have a distinct namespace from native-catalogue identity validation.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> fail(Reason).

%% Invalid prefixes never return partial parsed documents.
-spec fail(term()) -> no_return().
fail(Reason) -> error({spacetime_sdf, Reason}).
