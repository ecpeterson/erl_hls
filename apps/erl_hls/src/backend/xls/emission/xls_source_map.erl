-module(xls_source_map).
-moduledoc "Carries Erlang origins through DSLX formatting into readable right-column comments. Lowerers attach origins; xls_dslx supplies the structured document and xls_emitted writes complete annotated modules. Unannotated or ambiguous code remains unmapped; comments describe source association, not semantic equivalence.".
%% Source annotations accepted by lowerers and validated by the DSLX document.
-export([at/2, validate_location/1]).
%% Terminal formatting used by artifact finalization.
-export([render/1, render_annotated/1]).
-export_type([location/0, document/0]).

-doc "Original Erlang location, normally relative to the actor source directory; no source copy is implied.".
-type location() :: #{file := binary(), line := pos_integer()}.
-doc "Formatting document with explicit source scopes and deferred indentation; text leaves remain opaque.".
-type document() ::
    byte()
    | binary()
    | [document()]
    | {source, location(), document()}
    | {indent, document(), non_neg_integer()}.
%% Intermediate ranges use byte offsets until formatting establishes final line positions.
-type span() :: {non_neg_integer(), non_neg_integer(), location()}.
%% Span length and source identify equally precise active scopes during origin resolution.
-type scope() :: {pos_integer(), location()}.
%% Lexer state prevents annotation syntax from being inserted into a multiline literal.
-type lexical_state() :: normal | identifier | {quoted, byte(), boolean()}.
%% A surviving indented line records input start/end and output content start, excluding its newline.
-type line() :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}.

-doc "Attaches an existing Erlang file/line annotation; absent, generated or zero-line annotations leave syntax unchanged.".
-spec at(erl_anno:anno() | undefined, xls_dslx:value()) -> xls_dslx:value().
at(undefined, Value) ->
    Value;
at(0, Value) ->
    Value;
at(Anno, Value) ->
    case {erl_anno:generated(Anno), erl_anno:file(Anno), erl_anno:line(Anno)} of
        {false, File, Line} when File =/= undefined, Line > 0 ->
            xls_dslx:source(#{file => unicode:characters_to_binary(File), line => Line}, Value);
        _ ->
            Value
    end.

-doc "Rejects malformed source locations at the document boundary.".
-spec validate_location(term()) -> ok.
validate_location(#{file := File, line := Line} = Location) when
    map_size(Location) =:= 2,
    is_binary(File),
    byte_size(File) > 0,
    is_integer(Line),
    Line > 0
->
    ok;
validate_location(Location) ->
    error({invalid_source_location, Location}).

-doc "Renders unannotated bytes with the same formatting used by final source annotation.".
-spec render(document()) -> binary().
render(Document) ->
    {Bytes, _Spans} = flatten(Document),
    Bytes.

-doc "Adds readable source comments to complete DSLX output. Code bytes and the original final-newline status are preserved; multi-origin ranges use byte columns and aligned comment-only continuations.".
-spec render_annotated(document()) -> binary().
render_annotated(Document) ->
    {Bytes, Spans} = flatten(Document),
    iolist_to_binary(
        annotate_lines(binary:split(Bytes, <<"\n">>, [global]), resolve(Spans), 0, normal)
    ).

%% Resolve nested scopes before projecting onto lines; equal-sized conflicting origins remain unknown.
-spec resolve([span()]) -> [span()].
resolve(Spans) ->
    Events = lists:foldl(
        fun({Start, End, Source}, Acc) ->
            case Start < End of
                true ->
                    Key = {End - Start, Source},
                    add_event(End, {Key, -1}, add_event(Start, {Key, 1}, Acc));
                false ->
                    Acc
            end
        end,
        #{},
        Spans
    ),
    resolve_events(lists:sort(maps:to_list(Events)), #{}, []).

%% Group all starts and ends at the same byte boundary before choosing its following origin.
-spec add_event(non_neg_integer(), {scope(), 1 | -1}, #{non_neg_integer() => [{scope(), 1 | -1}]}) ->
    #{non_neg_integer() => [{scope(), 1 | -1}]}.
add_event(Position, Event, Events) ->
    maps:update_with(Position, fun(AtPosition) -> [Event | AtPosition] end, [Event], Events).

%% Active counts retain duplicate identical scopes without making them ambiguous.
-spec resolve_events([{non_neg_integer(), [{scope(), 1 | -1}]}], #{scope() => integer()}, [span()]) ->
    [span()].
resolve_events([], _Active, Acc) ->
    lists:reverse(Acc);
resolve_events([{Start, Changes} | Rest], Active, Acc) ->
    Updated = lists:foldl(
        fun({Key, Delta}, Counts) ->
            case maps:get(Key, Counts, 0) + Delta of
                0 -> maps:remove(Key, Counts);
                Count -> Counts#{Key => Count}
            end
        end,
        Active,
        Changes
    ),
    Next =
        case {Rest, narrowest(Updated)} of
            {[{End, _} | _], Source} when Source =/= none -> add_span({Start, End, Source}, Acc);
            _ -> Acc
        end,
    resolve_events(Rest, Updated, Next).

%% A broader fallback cannot resolve a tie between conflicting equally precise locations.
-spec narrowest(#{scope() => integer()}) -> none | location().
narrowest(Active) when map_size(Active) =:= 0 -> none;
narrowest(Active) ->
    Width = lists:min([Size || {Size, _} <- maps:keys(Active)]),
    case [Source || {Size, Source} <- maps:keys(Active), Size =:= Width] of
        [Source] -> Source;
        _ -> none
    end.

%% Adjacent identical origins need only one interval in the resolved byte stream.
-spec add_span(span(), [span()]) -> [span()].
add_span({Start, End, Source}, [{Previous, Start, Source} | Rest]) ->
    [{Previous, End, Source} | Rest];
add_span(Span, Acc) ->
    [Span | Acc].

%% Annotation-only continuation lines never alter the original code prefix or its byte columns.
-spec annotate_lines([binary()], [span()], non_neg_integer(), lexical_state()) -> iodata().
annotate_lines([], _Spans, _Offset, _State) ->
    [];
annotate_lines([Line | Rest], Spans, Offset, State) ->
    Remaining = lists:dropwhile(fun({_Start, End, _Source}) -> End =< Offset end, Spans),
    {CodeEnd, Comment, FinalState} = scan_line(Line, 0, State),
    Ranges = line_ranges(Line, Offset, CodeEnd, Remaining),
    Annotated =
        case {safe_comment(FinalState), Ranges} of
            {true, [_ | _]} -> annotated_line(Line, CodeEnd, Comment, Ranges);
            _ -> Line
        end,
    case Rest of
        [] ->
            Annotated;
        _ ->
            [
                Annotated,
                "\n",
                annotate_lines(
                    Rest,
                    Remaining,
                    Offset + byte_size(Line) + 1,
                    after_newline(FinalState)
                )
            ]
    end.

%% A marker may be appended after code or an actual line comment, never inside a literal.
-spec safe_comment(lexical_state()) -> boolean().
safe_comment(normal) -> true;
safe_comment(identifier) -> true;
safe_comment(_) -> false.

%% Newlines terminate identifiers and invalid character literals, but remain part of string literals.
-spec after_newline(lexical_state()) -> lexical_state().
after_newline({quoted, Quote, _Escape}) when Quote =:= $"; Quote =:= $` -> {quoted, Quote, false};
after_newline(_) -> normal.

%% This follows XLS scanner delimiters, including identifier ticks and apostrophe labels.
-spec scan_line(binary(), non_neg_integer(), lexical_state()) ->
    {non_neg_integer(), boolean(), lexical_state()}.
scan_line(Line, Position, State) when Position =:= byte_size(Line) -> {Position, false, State};
scan_line(Line, Position, {quoted, Quote, Escape}) ->
    Byte = binary:at(Line, Position),
    Next =
        case {Escape, Byte} of
            {true, _} -> {quoted, Quote, false};
            {false, $\\} -> {quoted, Quote, true};
            {false, Quote} -> normal;
            _ -> {quoted, Quote, false}
        end,
    scan_line(Line, Position + 1, Next);
scan_line(Line, Position, identifier) ->
    case identifier_byte(binary:at(Line, Position)) of
        true -> scan_line(Line, Position + 1, identifier);
        false -> scan_line(Line, Position, normal)
    end;
scan_line(Line, Position, normal) ->
    Byte = binary:at(Line, Position),
    case Byte of
        $/ when Position + 1 < byte_size(Line) ->
            case binary:at(Line, Position + 1) of
                $/ -> {Position, true, normal};
                _ -> scan_line(Line, Position + 1, normal)
            end;
        Quote when Quote =:= $"; Quote =:= $` ->
            scan_line(Line, Position + 1, {quoted, Quote, false});
        $' ->
            case character_literal(Line, Position) of
                true -> scan_line(Line, Position + 1, {quoted, $', false});
                false -> scan_line(Line, Position + 1, normal)
            end;
        _ ->
            Next =
                case identifier_start(Byte) of
                    true -> identifier;
                    false -> normal
                end,
            scan_line(Line, Position + 1, Next)
    end.

%% XLS distinguishes a character literal from an apostrophe label by its next two bytes.
-spec character_literal(binary(), non_neg_integer()) -> boolean().
character_literal(Line, Position) ->
    Position + 1 >= byte_size(Line) orelse binary:at(Line, Position + 1) =:= $\\ orelse
        Position + 2 >= byte_size(Line) orelse binary:at(Line, Position + 2) =:= $'.

%% ASCII identifier starts match the names emitted by the compiler.
-spec identifier_start(byte()) -> boolean().
identifier_start(Byte) ->
    (Byte >= $a andalso Byte =< $z) orelse (Byte >= $A andalso Byte =< $Z) orelse Byte =:= $_.

%% Macro suffixes and arbitrary trailing ticks are identifier characters in DSLX.
-spec identifier_byte(byte()) -> boolean().
identifier_byte(Byte) ->
    identifier_start(Byte) orelse (Byte >= $0 andalso Byte =< $9) orelse Byte =:= $! orelse
        Byte =:= $'.

%% Project disjoint origins onto non-whitespace code; neither comment text nor empty scopes count.
-spec line_ranges(binary(), non_neg_integer(), non_neg_integer(), [span()]) -> [span()].
line_ranges(Line, Offset, CodeEnd, Spans) ->
    Overlap = lists:takewhile(fun({Start, _End, _Source}) -> Start < Offset + CodeEnd end, Spans),
    Trimmed = lists:filtermap(
        fun({Start, End, Source}) ->
            First = trim_start(Line, max(Start - Offset, 0), min(End - Offset, CodeEnd)),
            Last = trim_end(Line, First, min(End - Offset, CodeEnd)),
            case First < Last of
                true -> {true, {First, Last, Source}};
                false -> false
            end
        end,
        Overlap
    ),
    lists:reverse(lists:foldl(fun(Span, Acc) -> merge_line_span(Line, Span, Acc) end, [], Trimmed)).

%% Joining same-origin pieces across whitespace cannot attribute any previously unknown code.
-spec merge_line_span(binary(), span(), [span()]) -> [span()].
merge_line_span(Line, {Start, End, Source}, [{Previous, PreviousEnd, Source} | Rest] = Acc) ->
    case trim_start(Line, PreviousEnd, Start) =:= Start of
        true -> [{Previous, End, Source} | Rest];
        false -> [{Start, End, Source} | Acc]
    end;
merge_line_span(_Line, Span, Acc) ->
    [Span | Acc].

%% Whitespace has no independent source-token ownership.
-spec trim_start(binary(), non_neg_integer(), non_neg_integer()) -> non_neg_integer().
trim_start(_Line, End, End) ->
    End;
trim_start(Line, Start, End) ->
    case whitespace(binary:at(Line, Start)) of
        true -> trim_start(Line, Start + 1, End);
        false -> Start
    end.

%% Retain original bytes while excluding trailing spaces from source-column ranges.
-spec trim_end(binary(), non_neg_integer(), non_neg_integer()) -> non_neg_integer().
trim_end(_Line, Start, Start) ->
    Start;
trim_end(Line, Start, End) ->
    case whitespace(binary:at(Line, End - 1)) of
        true -> trim_end(Line, Start, End - 1);
        false -> End
    end.

%% Scanner whitespace is ASCII; UTF-8 identifier bytes still contribute to byte columns.
-spec whitespace(byte()) -> boolean().
whitespace(Byte) -> Byte =:= 32 orelse (Byte >= 9 andalso Byte =< 13).

%% A single complete origin gets the compact form; all partial or mixed lines keep explicit ranges.
-spec annotated_line(binary(), non_neg_integer(), boolean(), [span(), ...]) -> iodata().
annotated_line(Line, CodeEnd, Comment, Ranges) ->
    Payloads =
        case Ranges of
            [{Start, End, Source}] ->
                case
                    trim_start(Line, 0, Start) =:= Start andalso
                        trim_end(Line, End, CodeEnd) =:= End
                of
                    true -> [origin_text(Source)];
                    false -> [range_text({Start, End, Source})]
                end;
            _ ->
                [range_text(Range) || Range <- Ranges]
        end,
    [First | Rest] = Payloads,
    %% @ columns align even when a preceding ordinary // comment already exists.
    At =
        case Comment of
            true -> max(83, byte_size(Line) + 2);
            false -> max(80, byte_size(Line) + 2) + 3
        end,
    Prefix =
        case Comment of
            true -> "@erl ";
            false -> "// @erl "
        end,
    CommentStart =
        case Comment of
            true -> At;
            false -> At - 3
        end,
    [
        Line,
        spaces(CommentStart - byte_size(Line)),
        Prefix,
        First,
        [["\n", spaces(At - 3), "// @erl+ ", Payload] || Payload <- Rest]
    ].

%% Files retain their exact spelling; JSON string escaping protects quotes and line delimiters.
-spec origin_text(location()) -> iodata().
origin_text(#{file := File, line := Line}) -> [json:encode(File), ":", integer_to_list(Line)].

%% Ranges refer to unchanged code bytes, with one-based columns and an exclusive end.
-spec range_text(span()) -> iodata().
range_text({Start, End, Source}) ->
    [integer_to_list(Start + 1), ":", integer_to_list(End + 1), " ", origin_text(Source)].

%% Spaces keep alignment deterministic without inserting tabs into generated source.
-spec spaces(non_neg_integer()) -> binary().
spaces(Count) -> binary:copy(<<" ">>, Count).

%% Source scopes surround their children without introducing marker bytes into generated text.
-spec flatten(document()) -> {binary(), [span()]}.
flatten(Bytes) when is_binary(Bytes) -> {Bytes, []};
flatten(Byte) when is_integer(Byte) -> {<<Byte>>, []};
flatten({source, Source, Document}) ->
    {Bytes, Spans} = flatten(Document),
    {Bytes, [{0, byte_size(Bytes), Source} | Spans]};
flatten({indent, Document, Spaces}) ->
    {Bytes, Spans} = flatten(Document),
    indent(Bytes, Spans, Spaces);
flatten(Documents) when is_list(Documents) ->
    {Parts, _Size} = lists:mapfoldl(
        fun(Document, Offset) ->
            {Bytes, Spans} = flatten(Document),
            {
                {Bytes, [{Start + Offset, End + Offset, Source} || {Start, End, Source} <- Spans]},
                Offset + byte_size(Bytes)
            }
        end,
        0,
        Documents
    ),
    {
        iolist_to_binary([Bytes || {Bytes, _Spans} <- Parts]),
        lists:append([Spans || {_Bytes, Spans} <- Parts])
    }.

%% Match xls_parse_io:indent/2 exactly: discard empty lines and terminate every remaining line.
-spec indent(binary(), [span()], non_neg_integer()) -> {binary(), [span()]}.
indent(Bytes, Spans, Spaces) ->
    Prefix = binary:copy(<<" ">>, Spaces),
    {Parts, _Offsets} = lists:mapfoldl(
        fun(Line, {Input, Output}) ->
            Size = byte_size(Line),
            case Size of
                0 ->
                    {{<<>>, none}, {Input + 1, Output}};
                _ ->
                    {{[Prefix, Line, "\n"], {Input, Input + Size, Output + Spaces}}, {
                        Input + Size + 1, Output + Spaces + Size + 1
                    }}
            end
        end,
        {0, 0},
        binary:split(Bytes, <<"\n">>, [global])
    ),
    Lines = list_to_tuple([Line || {_Bytes, Line} <- Parts, Line =/= none]),
    {
        iolist_to_binary([Part || {Part, _Line} <- Parts]),
        lists:filtermap(fun(Span) -> indent_span(Span, Lines) end, Spans)
    }.

%% Find the first and last surviving bytes; deleted blank lines cannot claim a source range.
-spec indent_span(span(), tuple()) -> false | {true, span()}.
indent_span({Start, End, Source}, Lines) ->
    First = lower_bound(Lines, fun({_Start, Stop, _Output}) -> Stop > Start end),
    Last = lower_bound(Lines, fun({Begin, _End, _Output}) -> Begin >= End end) - 1,
    case First =< Last andalso Start < End of
        true ->
            {FirstStart, _FirstEnd, FirstOutput} = element(First, Lines),
            {LastStart, LastEnd, LastOutput} = element(Last, Lines),
            {true, {
                FirstOutput + max(Start, FirstStart) - FirstStart,
                LastOutput + min(End, LastEnd) - LastStart,
                Source
            }};
        false ->
            false
    end.

%% Find the first ordered entry satisfying the monotonic predicate, or size+1 when absent.
-spec lower_bound(tuple(), fun((line()) -> boolean())) -> pos_integer().
lower_bound(Entries, Predicate) -> lower_bound(Entries, Predicate, 1, tuple_size(Entries) + 1).

%% Half-open bounds avoid touching the sentinel beyond the tuple.
-spec lower_bound(
    tuple(), fun((line()) -> boolean()), pos_integer(), pos_integer()
) -> pos_integer().
lower_bound(_Entries, _Predicate, Low, Low) ->
    Low;
lower_bound(Entries, Predicate, Low, High) ->
    Middle = (Low + High) div 2,
    case Predicate(element(Middle, Entries)) of
        true -> lower_bound(Entries, Predicate, Low, Middle);
        false -> lower_bound(Entries, Predicate, Middle + 1, High)
    end.
