-module(hls_spacetime_sdf_arcs).
-moduledoc "Projects validated SDF trees into pin-level annotations for offline native connectivity joins. The caller retains the original SDF and independently checks exact native pin correspondence. Conditions, transitions and unknown timing remain explicit; this is not gate sensitization or STA.".

%% Offline projection; no file or vendor-tool effects.
-export([project/1]).
-export_type([arc/0, projection/0]).

-doc "A native pin pair with preserved delay/condition forms. max_ps is an envelope over numeric delay slots, not slack or an executable period. Endpoint names decode SDF escapes but require independent catalogue membership checks.".
-type arc() :: #{
    kind := interconnect | iopath,
    cell := binary(),
    from := binary(),
    to := binary(),
    transition := binary() | null,
    guards := [hls_spacetime_sdf:form()],
    delay := [hls_spacetime_sdf:form()],
    max_ps := number() | null
}.

%% DELAY has no implicit annotation mode; only explicit wrappers supply one.
-type delay_mode() :: missing | absolute | increment.

%% An unsupported delay form stays inspectable and cannot silently supply a timing bound.
-type issue() :: #{
    cell := binary(),
    form := hls_spacetime_sdf:form(),
    reason := binary()
}.

-doc "Recognized SDF arc population with exact source identity. Uninterpreted DELAY forms remain issues. Original timing checks and all raw forms remain in the authoritative SDF sidecar.".
-type projection() :: #{
    schema := 1,
    source := hls_spacetime_sdf:source(),
    timescale := hls_spacetime_sdf:timescale(),
    arcs := [arc()],
    issues := [issue()],
    cells := non_neg_integer()
}.

-doc "Projects DELAY forms from an already validated SDF document. Recognizes INTERCONNECT and IOPATH under ABSOLUTE, INCREMENT, COND and CONDELSE. Conditions/transitions are retained without evaluation; increment annotations have no absolute numeric bound. Unsupported DELAY forms become issues. Missing or nested annotation modes reject rather than supply absolute timing. Raises {spacetime_sdf_arcs,Reason} for malformed recognized arc shapes.".
-spec project(hls_spacetime_sdf:parsed()) -> projection().
project(#{source := Source, timescale := Scale, cells := Cells}) ->
    Factor = scale(Scale),
    {Arcs, Issues} = lists:foldl(
        fun(#{instance := Instance, form := Form}, Acc) ->
            Cell = unescape(Instance),
            lists:foldl(
                fun(F, Current) ->
                    case tag(F) of
                        <<"DELAY">> -> walk(tl(F), Cell, [], missing, Factor, Current);
                        _ -> Current
                    end
                end,
                Acc,
                tl(Form)
            )
        end,
        {[], []},
        Cells
    ),
    #{
        schema => 1,
        source => Source,
        timescale => Scale,
        arcs => lists:reverse(Arcs),
        issues => lists:reverse(Issues),
        cells => length(Cells)
    }.

%% Wrapper expressions stay attached to every affected arc; none are selected dynamically.
-spec walk(
    [hls_spacetime_sdf:form()],
    binary(),
    [hls_spacetime_sdf:form()],
    delay_mode(),
    number(),
    {[arc()], [issue()]}
) -> {[arc()], [issue()]}.
walk(Forms, Cell, Guards, Mode, Factor, Acc) ->
    lists:foldl(
        fun(Form, {A, I} = Current) ->
            case tag(Form) of
                <<"ABSOLUTE">> ->
                    require(Mode =:= missing, nested_delay_mode),
                    walk(tl(Form), Cell, Guards, absolute, Factor, Current);
                <<"INCREMENT">> ->
                    require(Mode =:= missing, nested_delay_mode),
                    walk(tl(Form), Cell, Guards ++ [[hd(Form)]], increment, Factor, Current);
                <<"COND">> ->
                    conditional(Form, Cell, Guards, Mode, Factor, Current);
                <<"CONDELSE">> ->
                    conditional(Form, Cell, Guards, Mode, Factor, Current);
                <<"IOPATH">> ->
                    {[arc(iopath, Cell, tl(Form), Guards, Mode, Factor) | A], I};
                <<"INTERCONNECT">> ->
                    {[arc(interconnect, Cell, tl(Form), Guards, Mode, Factor) | A], I};
                <<"PATHPULSE">> ->
                    Current;
                <<"PATHPULSEPERCENT">> ->
                    Current;
                _ ->
                    {A, [
                        #{cell => Cell, form => Form, reason => <<"uninterpreted_delay_form">>} | I
                    ]}
            end
        end,
        Acc,
        Forms
    ).

%% The final conditional form is its arc; the preceding expression is retained verbatim.
-spec conditional(
    [hls_spacetime_sdf:form()],
    binary(),
    [hls_spacetime_sdf:form()],
    delay_mode(),
    number(),
    {[arc()], [issue()]}
) -> {[arc()], [issue()]}.
conditional(Form, Cell, Guards, Mode, Factor, Acc) ->
    require(length(Form) >= 2, conditional_shape),
    walk([lists:last(Form)], Cell, Guards ++ [lists:droplast(Form)], Mode, Factor, Acc).

%% Transitions modify the source pin; they do not create another native pin identity.
-spec arc(
    interconnect | iopath,
    binary(),
    [hls_spacetime_sdf:form()],
    [hls_spacetime_sdf:form()],
    delay_mode(),
    number()
) -> arc().
arc(Kind, Cell, [From, To | Delays], Guards, Mode, Factor) ->
    require(Mode =/= missing, missing_delay_mode),
    require(Delays =/= [], missing_delay),
    {Pin, Transition} = endpoint(From),
    {Destination, null} = endpoint(To),
    Max =
        case Mode of
            increment -> null;
            absolute -> maximum(Delays, Factor)
        end,
    #{
        kind => Kind,
        cell => Cell,
        from => Pin,
        to => Destination,
        transition => Transition,
        guards => Guards,
        delay => Delays,
        max_ps => Max
    };
arc(_, _, _, _, _, _) ->
    error({spacetime_sdf_arcs, arc_shape}).

%% Native spelling is resolved later against the complete catalogue, never guessed from suffixes.
-spec endpoint(hls_spacetime_sdf:form()) -> {binary(), binary() | null}.
endpoint(#{kind := symbol, lexeme := Name}) ->
    {unescape(Name), null};
endpoint([#{kind := symbol, lexeme := Edge}, #{kind := symbol, lexeme := Name}]) ->
    require(
        lists:member(Edge, [
            <<"posedge">>, <<"negedge">>, <<"01">>, <<"10">>, <<"0z">>, <<"z1">>, <<"1z">>, <<"z0">>
        ]),
        transition
    ),
    {unescape(Name), Edge};
endpoint(_) ->
    error({spacetime_sdf_arcs, endpoint}).

%% Empty or unsupported slots prevent a numeric envelope; absent timing is never zero.
-spec maximum([hls_spacetime_sdf:form()], number()) -> number() | null.
maximum(Forms, Factor) ->
    Values = lists:append([numbers(F) || F <- Forms]),
    case Values =/= [] andalso not lists:member(unknown, Values) of
        true -> lists:max(Values) * Factor;
        false -> null
    end.

%% Every min/typ/max slot remains represented independently of the process corner.
-spec numbers(hls_spacetime_sdf:form()) -> [number() | unknown].
numbers([]) ->
    [unknown];
numbers(Forms) when is_list(Forms) -> lists:append([numbers(F) || F <- Forms]);
numbers(#{kind := symbol, lexeme := Value}) ->
    [number(P) || P <- binary:split(Value, <<":">>, [global])];
numbers(_) ->
    [unknown].

%% Decimal conversion accepts complete finite tokens, retaining unknowns conservatively.
-spec number(binary()) -> number() | unknown.
number(Value) ->
    case
        re:run(Value, <<"^[+-]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$">>, [
            {capture, none}
        ])
    of
        match ->
            try
                binary_to_integer(Value)
            catch
                error:badarg ->
                    try
                        binary_to_float(float_spelling(Value))
                    catch
                        error:badarg -> unknown
                    end
            end;
        nomatch ->
            unknown
    end.

%% Erlang float syntax requires a leading digit and a decimal point before an exponent.
-spec float_spelling(binary()) -> binary().
float_spelling(Value) ->
    [Mantissa0 | Exponent] = re:split(Value, <<"[eE]">>, [{return, binary}]),
    Mantissa =
        case Mantissa0 of
            <<".", R/binary>> -> <<"0.", R/binary>>;
            <<"-.", R/binary>> -> <<"-0.", R/binary>>;
            <<"+.", R/binary>> -> <<"+0.", R/binary>>;
            _ -> Mantissa0
        end,
    M =
        case binary:match(Mantissa, <<".">>) of
            nomatch -> <<Mantissa/binary, ".0">>;
            _ -> Mantissa
        end,
    case Exponent of
        [] -> M;
        [E] -> <<M/binary, "e", E/binary>>
    end.

%% Picoseconds are only the envelope's output unit; original timescale remains in the projection.
-spec scale(hls_spacetime_sdf:timescale()) -> number().
scale(#{magnitude := Magnitude, unit := Unit}) ->
    N = number(Magnitude),
    require(is_number(N) andalso N > 0, timescale),
    N *
        maps:get(Unit, #{
            fs => 0.001, ps => 1, ns => 1000, us => 1000000, ms => 1000000000, s => 1000000000000
        }).

%% SDF backslashes quote the following byte, including brackets and hierarchy separators.
-spec unescape(binary()) -> binary().
unescape(Value) -> unescape(Value, <<>>).

%% Dangling escapes cannot identify complete native names.
-spec unescape(binary(), binary()) -> binary().
unescape(<<$\\, C, Rest/binary>>, Acc) -> unescape(Rest, <<Acc/binary, C>>);
unescape(<<$\\>>, _) -> error({spacetime_sdf_arcs, dangling_escape});
unescape(<<C, Rest/binary>>, Acc) -> unescape(Rest, <<Acc/binary, C>>);
unescape(<<>>, Acc) -> Acc.

%% Unrecognized metadata cannot masquerade as a supported timing construct.
-spec tag(hls_spacetime_sdf:form()) -> binary().
tag([#{kind := symbol, lexeme := Tag} | _]) -> Tag;
tag(_) -> <<>>.

%% Projection errors are distinct from lexical reader errors.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> error({spacetime_sdf_arcs, Reason}).
