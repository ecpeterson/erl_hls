-module(hls_reply_book).
-moduledoc "Bounded caller ownership shared by CPU server and state-machine adapters.".
-export([new/1, admit/4, complete/2]).
-export_type([book/0]).

-doc "Activation-local handles, their callers and allowed reply records; completed tokens are never reissued.".
-type book() :: #{limit := pos_integer(), next := pos_integer(),
    callers := #{non_neg_integer() => {gen_server:from(), [atom()]}}}.

-doc "Creates an empty book with capacity for N retained calls.".
-spec new(1..255) -> book().
new(N) -> #{limit => N, next => 1, callers => #{}}.

-doc "Admits a caller, or replies busy without calling the application; sequence exhaustion raises an error.".
-spec admit(0..255, gen_server:from(), [atom()], book()) ->
    {ok, pos_integer(), book()} | full.
admit(_Tag, _From, _Replies, #{next := Sequence}) when Sequence >= (1 bsl 56) ->
    error(reply_handle_exhausted);
admit(_Tag, From, _Replies, #{limit := Limit, callers := Callers}) when map_size(Callers) >= Limit ->
    gen_server:reply(From, {error, {remote_error, busy}}),
    full;
admit(Tag, From, Replies, Book = #{next := Sequence, callers := Callers}) ->
    Handle = (Sequence bsl 8) bor Tag,
    {ok, Handle, Book#{next := Sequence + 1, callers := Callers#{Handle => {From, Replies}}}}.

-doc "Checks and completes at most one live caller; an absent or already completed handle does nothing.".
-spec complete(none | {reply, non_neg_integer(), term()}, book()) -> book().
complete(none, Book) -> Book;
complete({reply, Token, Value}, Book = #{callers := Callers}) ->
    case maps:take(Token, Callers) of
        error -> Book;
        {{From, Allowed}, Rest} ->
            case is_tuple(Value) andalso tuple_size(Value) > 0 andalso
                    lists:member(element(1, Value), Allowed) of
                true -> ok;
                false -> error({reply_contract, Value, Allowed})
            end,
            gen_server:reply(From, Value),
            Book#{callers := Rest}
    end.
