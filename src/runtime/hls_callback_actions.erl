-module(hls_callback_actions).
-moduledoc "Validates one reply followed by one named internal step.".
-export([split/3]).

-doc "Returns an optional reply and continuation; rejects excess, reordered or undeclared actions.".
-spec split(term(), server | statem, [atom()]) ->
    {none | {reply, non_neg_integer(), term()}, none | atom()}.
split([{reply, From, Value} | Tail], Kind, Names) when is_integer(From), From >= 0 ->
    {{reply, From, Value}, continuation(Tail, Kind, Names)};
split(Actions, Kind, Names) -> {none, continuation(Actions, Kind, Names)}.

%% The behaviours retain their OTP vocabulary while sharing the finite bound.
-spec continuation(term(), server | statem, [atom()]) -> none | atom().
continuation([], _Kind, _Names) -> none;
continuation([{continue, Name}], server, Names) -> hls_continuation:require(Name, Names);
continuation([{next_event, internal, Name}], statem, Names) -> hls_continuation:require(Name, Names);
continuation(Actions, Kind, _Names) -> error({invalid_hls_callback_actions, Kind, Actions}).
