-module(hls_cli).
-moduledoc "Small command-line helpers shared by compiler and downstream build frontends. No commands or build policy are registered here.".
-export([main/2, options/2, required/2, integer/2]).
-export_type([option/0]).

-doc "An accepted spelling, fixed result key and value mode. Repeated values retain command-line order; other duplicates fail.".
-type option() :: {string(), atom(), flag | value | repeat}.

-doc "Runs a frontend with plain VM arguments and exits zero on success or one with a diagnostic on failure. HLS_DEBUG=1 includes the stack trace. Does not launch tools or shells.".
-spec main(string(), fun(([string()]) -> ok)) -> no_return().
main(Name, Run) ->
    try Run(init:get_plain_arguments()) of
        ok -> halt(0)
    catch Class:Reason:Stack ->
        io:format(standard_error, "~s: ~tp~n", [Name, Reason]),
        case os:getenv("HLS_DEBUG") of
            "1" -> io:format(standard_error, "~p:~tp~n~tp~n", [Class, Reason, Stack]);
            _ -> ok
        end,
        halt(1)
    end.

-doc "Parses only declared options, without creating atoms. Value options require separate arguments; missing, unknown and duplicate options fail. Positional arguments are handled by the calling frontend.".
-spec options([string()], [option()]) -> map().
options(Args, Spec) -> options(Args, Spec, #{}).

%% One parser owns spelling and duplicate handling without knowing any application.
-spec options([string()], [option()], map()) -> map().
options([], _, Acc) -> Acc;
options([Name | Rest], Spec, Acc) ->
    {Key, Mode} = case lists:keyfind(Name, 1, Spec) of
        {Name, K, M} -> {K, M};
        false -> error({unknown_option, Name})
    end,
    case Mode =/= repeat andalso maps:is_key(Key, Acc) of
        true -> error({duplicate_option, Name});
        false -> ok
    end,
    case {Mode, Rest} of
        {flag, _} -> options(Rest, Spec, Acc#{Key => true});
        {_, []} -> error({missing_option_value, Name});
        {_, [[$- | _] | _]} -> error({missing_option_value, Name});
        {repeat, [Value | Tail]} -> options(Tail, Spec, Acc#{Key => maps:get(Key, Acc, []) ++ [Value]});
        {value, [Value | Tail]} -> options(Tail, Spec, Acc#{Key => Value})
    end.

-doc "Returns a required option or raises a concise missing-option diagnostic.".
-spec required(atom(), map()) -> string().
required(Key, Options) ->
    case maps:find(Key, Options) of
        {ok, Value} -> Value;
        error -> error({missing_option, Key})
    end.

-doc "Parses a decimal integer with a named diagnostic; the caller checks domain bounds.".
-spec integer(atom(), string()) -> integer().
integer(Key, Value) ->
    try list_to_integer(Value) catch error:badarg -> error({invalid_integer, Key, Value}) end.
