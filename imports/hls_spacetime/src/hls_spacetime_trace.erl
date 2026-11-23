-module(hls_spacetime_trace).
-include_lib("kernel/include/file.hrl").
-moduledoc """
Reads bounded passive samples in the current 32-bit protocol-stream capture dialect, with eleven fixed public fields and declared taps. The external recorder owns clock sampling and loss detection; this module checks the run-length stream before backend adapters interpret accepted operations. It does not assign semantic dependencies or treat value changes as transactions.
""".
%% Offline producer boundary; never starts a simulator or writes files.
-export([read/1, fold/3]).
-export_type([trace/0, signal/0, span/0]).

-doc "One named sampled value. Public signals have path public; taps retain their exact simulator path.".
-type signal() :: #{id := binary(), width := pos_integer(), path := binary()}.
-doc "Consecutive identical pre-edge samples; operations may occur on every edge even when values repeat.".
-type span() :: #{
    first := non_neg_integer(), count := pos_integer(), values := [non_neg_integer()]
}.
-doc "Validated sample coverage with explicit termination. Incomplete traces cannot establish a whole-window witness.".
-type trace() :: #{
    signals := [signal()],
    spans := [span()],
    end_cycle := non_neg_integer(),
    complete := boolean(),
    cause := binary(),
    records := non_neg_integer()
}.

%% Registered S3 ceilings apply before parsing or expanding observations.
-define(MAX_BYTES, (256 * 1024 * 1024)).
-define(MAX_CYCLES, 4000000).
-define(MAX_RECORDS, 1000000).

-doc "Reads a newline-terminated trace with exact header, field widths, consecutive spans and a final coverage footer. Erlang normalizes CRLF endings to LF; decoded accounting uses those normalized rows. Raises {spacetime_trace, Reason}; rejects overflow, malformed/truncated rows and falsely complete loss reports.".
-spec read(file:filename_all()) -> trace().
read(Path) ->
    {ok, #file_info{size = Size}} = file:read_file_info(Path),
    require(Size =< ?MAX_BYTES, file_limit),
    {ok, File} = file:open(Path, [read, raw, binary, {read_ahead, 65536}]),
    try
        Header = row(File),
        require(Header =:= [<<"H">>, <<"spacetime_cycle_trace">>, <<"1">>], header),
        Public = public(),
        PublicRow = row(File),
        require(PublicRow =:= [<<"P">> | [maps:get(id, P) || P <- Public]], public_fields),
        Budget = 4096 + row_bytes(Header) + row_bytes(PublicRow),
        parse(File, Public, [], 0, 0, Budget, false)
    after
        ok = file:close(File)
    end.

-doc "Visits each recorded edge without materializing an expanded sample table. The callback receives cycle and the signal-id map; equal runs still invoke it once per edge. Only accepts a previously checked trace.".
-spec fold(fun((non_neg_integer(), #{binary() => non_neg_integer()}, Acc) -> Acc), Acc, trace()) ->
    Acc.
fold(Fun, Acc, #{signals := Signals, spans := Spans}) ->
    Names = [maps:get(id, S) || S <- Signals],
    lists:foldl(
        fun(#{first := C, count := N, values := Values}, A) ->
            Sample = maps:from_list(lists:zip(Names, Values)),
            edges(C, C + N, Sample, Fun, A)
        end,
        Acc,
        Spans
    ).

%% This fixed public prefix records offered traffic as well as accepted results.
-spec public() -> [signal()].
public() ->
    [
        #{id => N, width => W, path => <<"public">>}
     || {N, W} <-
            [
                {<<"reset">>, 1},
                {<<"input_valid">>, 1},
                {<<"input_data">>, 32},
                {<<"input_last">>, 1},
                {<<"output_ready">>, 1},
                {<<"input_ready">>, 1},
                {<<"output_valid">>, 1},
                {<<"output_data">>, 32},
                {<<"output_last">>, 1},
                {<<"fault">>, 1},
                {<<"running">>, 1}
            ]
    ].

%% Taps may only precede data; the footer is mandatory and consumes the entire file.
-spec parse(
    file:io_device(),
    [signal()],
    [span()],
    non_neg_integer(),
    non_neg_integer(),
    non_neg_integer(),
    boolean()
) -> trace().
parse(File, Signals, Spans, Next, Count, Expanded, Started) ->
    case row(File) of
        [<<"T">>, Id, Width0, Path] = TapRow when not Started ->
            Width = decimal(Width0),
            require(Width > 0 andalso Width =< 65536, tap_width),
            wire_text(Id),
            wire_text(Path),
            require(
                not lists:any(fun(#{id := Existing}) -> Existing =:= Id end, Signals),
                duplicate_signal
            ),
            require(length(Signals) < 4096 + length(public()), signal_limit),
            require(
                not lists:any(
                    fun(#{path := P, width := W}) -> P =:= Path andalso W =/= Width end,
                    lists:nthtail(length(public()), Signals)
                ),
                shared_tap_width
            ),
            NextSignals = Signals ++ [#{id => Id, width => Width, path => Path}],
            TapBytes = lists:sum([
                (W + 3) div 4 + 1
             || #{width := W} <- lists:nthtail(length(public()), NextSignals)
            ]),
            require(TapBytes + 256 =< 1024 * 1024, sample_width_limit),
            Size = Expanded + row_bytes(TapRow),
            require(Size =< ?MAX_BYTES, decoded_limit),
            parse(File, NextSignals, Spans, Next, Count, Size, false);
        [<<"S">>, First0, Length0 | Encoded] ->
            First = decimal(First0),
            N = decimal(Length0),
            require(First =:= Next andalso N > 0, sample_coverage),
            require(First + N =< ?MAX_CYCLES andalso Count < ?MAX_RECORDS, sample_limit),
            require(length(Encoded) =:= length(Signals), sample_width),
            Size = Expanded + N * (32 + lists:sum([byte_size(V) + 1 || V <- Encoded])),
            require(Size =< ?MAX_BYTES, decoded_limit),
            Values = [hex(V, maps:get(width, S)) || {V, S} <- lists:zip(Encoded, Signals)],
            Span = #{first => First, count => N, values => Values},
            parse(File, Signals, [Span | Spans], First + N, Count + 1, Size, true);
        [<<"F">>, End0, Status, Samples0, Records0, Bytes0, Cause] ->
            require(
                decimal(End0) =:= Next andalso decimal(Samples0) =:= Next andalso
                    decimal(Records0) =:= Count,
                footer_coverage
            ),
            Bound = decimal(Bytes0),
            require(Bound =:= Expanded andalso Bound =< ?MAX_BYTES, decoded_limit),
            require(Status =:= <<"complete">> orelse Status =:= <<"incomplete">>, footer_status),
            require(
                byte_size(Cause) > 0 andalso byte_size(Cause) =< 200 andalso cause_chars(Cause) andalso
                    ((Status =:= <<"complete">>) =:= (Cause =:= <<"ok">>)),
                footer_cause
            ),
            require(row(File) =:= eof, trailing_data),
            #{
                signals => Signals,
                spans => lists:reverse(Spans),
                end_cycle => Next,
                complete => Status =:= <<"complete">>,
                cause => Cause,
                records => Count
            };
        eof ->
            fail(missing_footer);
        _ ->
            fail(row)
    end.

%% file:read_line normalizes CRLF; embedded controls and final partial lines remain invalid.
-spec row(file:io_device()) -> [binary()] | eof.
row(File) ->
    case file:read_line(File) of
        eof ->
            eof;
        {ok, Line} ->
            require(
                byte_size(Line) =< 1024 * 1024 + 1 andalso binary:last(Line) =:= $\n,
                truncated_or_large_line
            ),
            binary:split(binary:part(Line, 0, byte_size(Line) - 1), <<"\t">>, [global]);
        {error, Why} ->
            fail({read, Why})
    end.

%% Decimal metadata is canonical and bounded before use as an allocation or loop count.
-spec decimal(binary()) -> non_neg_integer().
decimal(Bin) ->
    require(
        byte_size(Bin) > 0 andalso byte_size(Bin) =< 16 andalso canonical(Bin) andalso
            digits(Bin, decimal),
        decimal
    ),
    binary_to_integer(Bin).

%% Wide samples use hexadecimal strings; no floating-point conversion occurs.
-spec hex(binary(), pos_integer()) -> non_neg_integer().
hex(Bin, Width) ->
    require(
        byte_size(Bin) > 0 andalso byte_size(Bin) =< (Width + 3) div 4 andalso canonical(Bin) andalso
            digits(Bin, hex),
        hex
    ),
    N = binary_to_integer(Bin, 16),
    require(N < (1 bsl Width), value_width),
    N.

%% Restrict the wire grammar to ASCII digits without signs or whitespace.
-spec digits(binary(), decimal | hex) -> boolean().
digits(<<>>, _) -> true;
digits(<<C, Rest/binary>>, Mode) when C >= $0, C =< $9 -> digits(Rest, Mode);
digits(<<C, Rest/binary>>, hex) when C >= $a, C =< $f -> digits(Rest, hex);
digits(_, _) -> false.

%% A single zero is canonical; padding is never part of an integer identity.
-spec canonical(binary()) -> boolean().
canonical(<<$0, _First, _Rest/binary>>) -> false;
canonical(_) -> true.

%% Printable ASCII metadata cannot conceal record delimiters or allocate unbounded IDs.
-spec wire_text(binary()) -> ok.
wire_text(Bin) ->
    require(byte_size(Bin) > 0 andalso byte_size(Bin) =< 4096 andalso ascii(Bin), tap_identity).

%% Spaces are permitted in identifiers/paths, but control characters are not.
-spec ascii(binary()) -> boolean().
ascii(<<>>) -> true;
ascii(<<C, Rest/binary>>) when C >= 32, C =< 126 -> ascii(Rest);
ascii(_) -> false.

%% Footer causes have the recorder's bounded token grammar, independent of prose messages.
-spec cause_chars(binary()) -> boolean().
cause_chars(<<>>) ->
    true;
cause_chars(<<C, Rest/binary>>) when
    C >= $a, C =< $z;
    C >= $A, C =< $Z;
    C >= $0, C =< $9;
    C =:= $_;
    C =:= $-
->
    cause_chars(Rest);
cause_chars(_) ->
    false.

%% A row with N fields occupies their bytes plus N-1 tabs and one final newline.
-spec row_bytes([binary()]) -> non_neg_integer().
row_bytes(Fields) -> lists:sum([byte_size(F) + 1 || F <- Fields]).

%% Tail recursion keeps equal-value runs bounded in memory.
-spec edges(
    non_neg_integer(), non_neg_integer(), map(), fun((non_neg_integer(), map(), Acc) -> Acc), Acc
) -> Acc.
edges(End, End, _, _, Acc) -> Acc;
edges(C, End, Sample, Fun, Acc) -> edges(C + 1, End, Sample, Fun, Fun(C, Sample, Acc)).

%% Parser diagnostics identify the invalid contract, not partially decoded artifacts.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> fail(Reason).

%% Keep malformed recorder evidence separate from semantic artifact errors.
-spec fail(term()) -> no_return().
fail(Reason) -> error({spacetime_trace, Reason}).
