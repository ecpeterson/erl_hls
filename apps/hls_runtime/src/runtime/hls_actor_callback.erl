-module(hls_actor_callback).
-moduledoc "Adapts server and state-function callbacks to the common native actor scheduler. Owns only callback vocabulary and result normalization; mailbox selection, replies and domain lifetime remain in hls_statem and hls_reply_book.".
%% Shared callback adaptation, including explicit server startup without compiler metadata.
-export([kind/1, initialize/3, invoke/6]).
-export_type([kind/0]).

-doc "Supported source callback vocabularies.".
-type kind() :: server | statem.

-doc "Recognizes an hls_gs module; state-machine modules retain their existing default.".
-spec kind(module()) -> kind().
kind(Module) ->
    Attributes = Module:module_info(attributes),
    Behaviors = lists:append(
        proplists:get_all_values(behaviour, Attributes) ++
            proplists:get_all_values(behavior, Attributes)
    ),
    case lists:member(hls_gs, Behaviors) of
        true -> server;
        false -> statem
    end.

-doc "Runs the source initializer, supplying the server's one inert control state.".
-spec initialize(kind(), module(), term()) -> {ok, atom(), term()}.
initialize(server, Module, Arg) -> {ok, hls_server, Module:init(Arg)};
initialize(statem, Module, Arg) -> Module:init(Arg).

-doc "Invokes one source callback and returns the common entry or event result without committing effects.".
-spec invoke(kind(), module(), atom(), term(), term(), term()) -> term().
invoke(statem, Module, Phase, Event, Message, Data) ->
    Module:Phase(Event, Message, Data);
invoke(server, _Module, hls_server, enter, _Old, Data) ->
    {Data, []};
invoke(server, Module, hls_server, {call, From}, Message, Data) ->
    Result =
        case erlang:function_exported(Module, handle_call, 3) of
            true ->
                Module:handle_call(Message, From, Data);
            false ->
                {reply, Reply, Next} = Module:handle_call(Message, Data),
                {reply, Reply, Next}
        end,
    normalize(Result, From, hls_continuation:names(Module));
invoke(server, Module, hls_server, cast, Message, Data) ->
    Result = Module:handle_cast(Message, Data),
    Checked =
        case erlang:function_exported(Module, handle_call, 3) of
            true ->
                Result;
            false ->
                {noreply, Next} = Result,
                {noreply, Next}
        end,
    normalize(Checked, none, hls_continuation:names(Module));
invoke(server, Module, hls_server, internal, Name, Data) ->
    normalize(Module:handle_continue(Name, Data), none, hls_continuation:names(Module)).

%% Keep server action validation and ordering, then expose the ordinary actor actions.
-spec normalize(term(), none | non_neg_integer(), [atom()]) -> term().
normalize({reply, Reply, Data}, From, Names) when is_integer(From) ->
    normalize({noreply, Data, [{reply, From, Reply}]}, none, Names);
normalize({reply, Reply, Data, {continue, Name}}, From, Names) when is_integer(From) ->
    normalize({noreply, Data, [{reply, From, Reply}, {continue, Name}]}, none, Names);
normalize({noreply, Data}, _, _) ->
    {hls_server, Data, consume};
normalize({noreply, Data, {continue, Name}}, From, Names) ->
    normalize({noreply, Data, [{continue, Name}]}, From, Names);
normalize({noreply, Data, Actions}, _, Names) ->
    {Reply, Continue} = hls_callback_actions:split(Actions, server, Names),
    Replies =
        case Reply of
            none -> [];
            _ -> [Reply]
        end,
    Events =
        case Continue of
            none -> [];
            _ -> [{next_event, internal, Continue}]
        end,
    {hls_server, Data, consume, Replies ++ Events};
normalize(Result, _, _) ->
    error({invalid_hls_server_result, Result}).
