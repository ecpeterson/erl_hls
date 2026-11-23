-module(hls_cli).
-moduledoc """
Command-line parsing and diagnostic helpers shared by hls_compile_cli and downstream build frontends. Delegates owned error presentation to hls_diagnostic; commands, emission policy and external tool execution belong to callers.
""".
%% Command execution and diagnostic boundary.
-export([main/2]).

%% Option parsing and checked values.
-export([options/2, required/2, integer/2]).
%% Shared type contracts.
-export_type([option/0]).

-doc "An accepted spelling, fixed result key and value mode. Repeat options accumulate in command-line order; values use the last occurrence and flags are idempotent.".
-type option() :: {string(), atom(), flag | value | repeat}.

-doc "Runs a frontend with plain VM arguments, reserving --diagnostics text|json for failure rendering. Tagged failures use their owned diagnostic; unexpected exceptions always retain class, reason and stack. Exits zero on success or one on failure.".
-spec main(string(), fun(([string()]) -> ok)) -> no_return().
main(Name, Run) ->
    try diagnostic_options(init:get_plain_arguments(), "text", []) of
        {Mode, Args} -> execute(Name, Run, Mode, Args)
    catch
        error:{hls_diagnostic, Diagnostic}:Stack ->
            report_diagnostic(Name, text, Diagnostic, Stack),
            halt(1);
        Class:Reason:Stack ->
            report_exception(Name, text, Class, Reason, Stack),
            halt(1)
    end.

%% Keep global rendering options separate from frontend command vocabularies.
-spec diagnostic_options([string()], string(), [string()]) -> {text | json, [string()]}.
diagnostic_options([], Value, Acc) ->
    Mode =
        case Value of
            "text" ->
                text;
            "json" ->
                json;
            _ ->
                hls_diagnostic:raise(
                    arguments,
                    invalid_diagnostics,
                    <<"Diagnostic format must be text or json">>,
                    #{option => <<"--diagnostics">>, value => unicode:characters_to_binary(Value)}
                )
        end,
    {Mode, lists:reverse(Acc)};
diagnostic_options(["--diagnostics", [$- | _] | _], _Mode, _Acc) ->
    hls_diagnostic:raise(arguments, missing_option_value, <<"Option requires a value">>, #{
        option => <<"--diagnostics">>
    });
diagnostic_options(["--diagnostics", Value | Rest], _Mode, Acc) ->
    diagnostic_options(Rest, Value, Acc);
diagnostic_options(["--diagnostics"], _Mode, _Acc) ->
    hls_diagnostic:raise(arguments, missing_option_value, <<"Option requires a value">>, #{
        option => <<"--diagnostics">>
    });
diagnostic_options([Arg | Rest], Mode, Acc) ->
    diagnostic_options(Rest, Mode, [Arg | Acc]).

%% Only an owned diagnostic is rendered as an expected failure.
-spec execute(string(), fun(([string()]) -> ok), text | json, [string()]) -> no_return().
execute(Name, Run, Mode, Args) ->
    try Run(Args) of
        ok -> halt(0)
    catch
        error:{hls_diagnostic, Diagnostic}:Stack ->
            report_diagnostic(Name, Mode, Diagnostic, Stack),
            halt(1);
        Class:Reason:Stack ->
            report_exception(Name, Mode, Class, Reason, Stack),
            halt(1)
    end.

%% Debugging adds the original stack without breaking the one-object JSON contract.
-spec report_diagnostic(string(), text | json, hls_diagnostic:diagnostic(), [term()]) -> ok.
report_diagnostic(Name, text, Diagnostic, Stack) ->
    io:put_chars(standard_error, [Name, ": ", hls_diagnostic:format(Diagnostic), "\n"]),
    case os:getenv("HLS_DEBUG") of
        "1" -> io:format(standard_error, "~tp~n", [Stack]);
        _ -> ok
    end;
report_diagnostic(_Name, json, Diagnostic, Stack) ->
    Report =
        case os:getenv("HLS_DEBUG") of
            "1" -> Diagnostic#{stack => Stack};
            _ -> Diagnostic
        end,
    io:put_chars(standard_error, [json:encode(hls_diagnostic:json_value(Report)), "\n"]).

%% Unexpected failures are not relabeled as user configuration errors.
-spec report_exception(string(), text | json, error | exit | throw, term(), [term()]) -> ok.
report_exception(Name, text, Class, Reason, Stack) ->
    io:format(standard_error, "~s: ~p:~tp~n~tp~n", [Name, Class, Reason, Stack]);
report_exception(_Name, json, Class, Reason, Stack) ->
    io:put_chars(standard_error, [
        json:encode(
            hls_diagnostic:json_value(
                #{exception => Class, reason => Reason, stack => Stack}
            )
        ),
        "\n"
    ]).

-doc "Parses only declared options, without creating atoms. Value options require separate arguments; missing and unknown options fail. Later values override earlier values for the same key, including aliases; repeat options accumulate and flags may repeat. Positional arguments are handled by the calling frontend.".
-spec options([string()], [option()]) -> map().
options(Args, Spec) -> options(Args, Spec, #{}).

%% Resolve spelling and precedence before frontends validate effective values.
-spec options([string()], [option()], map()) -> map().
options([], _, Acc) ->
    Acc;
options([Name | Rest], Spec, Acc) ->
    {Key, Mode} =
        case lists:keyfind(Name, 1, Spec) of
            {Name, K, M} ->
                {K, M};
            false ->
                hls_diagnostic:raise(arguments, unknown_option, <<"Unknown option">>, #{
                    option => unicode:characters_to_binary(Name)
                })
        end,
    case {Mode, Rest} of
        {flag, _} ->
            options(Rest, Spec, Acc#{Key => true});
        {_, []} ->
            hls_diagnostic:raise(arguments, missing_option_value, <<"Option requires a value">>, #{
                option => unicode:characters_to_binary(Name)
            });
        {_, [[$- | _] | _]} ->
            hls_diagnostic:raise(arguments, missing_option_value, <<"Option requires a value">>, #{
                option => unicode:characters_to_binary(Name)
            });
        {repeat, [Value | Tail]} ->
            options(Tail, Spec, Acc#{Key => maps:get(Key, Acc, []) ++ [Value]});
        {value, [Value | Tail]} ->
            options(Tail, Spec, Acc#{Key => Value})
    end.

-doc "Returns a required option or raises a concise missing-option diagnostic.".
-spec required(atom(), map()) -> string().
required(Key, Options) ->
    case maps:find(Key, Options) of
        {ok, Value} ->
            Value;
        error ->
            hls_diagnostic:raise(arguments, missing_option, <<"Required option is missing">>, #{
                option => Key
            })
    end.

-doc "Parses a decimal integer with a named diagnostic; the caller checks domain bounds.".
-spec integer(atom(), string()) -> integer().
integer(Key, Value) ->
    try
        list_to_integer(Value)
    catch
        error:badarg ->
            hls_diagnostic:raise(
                arguments,
                invalid_integer,
                <<"Option requires a decimal integer">>,
                #{option => Key, value => unicode:characters_to_binary(Value)}
            )
    end.
