%%%% One source of truth for hls_gs request kinds and allowed reply records.
-module(hls_service_contract).
-moduledoc false.

-export([from_forms/1, from_module/1, groups/2, call_arity/1]).
-export_type([contract/0]).

-doc "Allowed reply tags by call request, plus supported cast tags.".
-type contract() :: #{calls := #{atom() => [atom(), ...]}, casts := [atom()],
    pending_calls => 1..255, continuations => [atom()]}.

-doc "Validates request/reply declarations and returns allowed call replies and cast tags.".
-spec from_forms([hls_source:form()]) -> contract().
from_forms(Forms) ->
    Public = xls_parse:find_tags(Forms),
    {Calls, Casts} = request_tags(Forms),
    case [Tag || Tag <- Calls ++ Casts, not lists:member(Tag, Public)] of
        [] -> ok;
        Undeclared -> error({undeclared_hls_gs_callback_tags, Undeclared})
    end,
    case [Tag || Tag <- Calls, lists:member(Tag, Casts)] of
        [] -> ok;
        Ambiguous -> error({ambiguous_hls_gs_callback_tags, Ambiguous})
    end,
    Declarations = [Value || {attribute, _, hls_replies, Value} <- Forms],
    Replies = lists:foldl(fun(Entries, Acc) when is_list(Entries) ->
        lists:foldl(fun(Entry, Map) -> declaration(Entry, Public, Map) end, Acc, Entries);
        (Value, _) -> error({invalid_hls_replies, Value})
    end, #{}, Declarations),
    case {Calls -- maps:keys(Replies), maps:keys(Replies) -- Calls} of
        {[], []} -> extended(Forms, #{calls => Replies, casts => Casts});
        {Missing, Extra} -> error({hls_reply_requests, #{missing => Missing, extra => Extra}})
    end.

%% State functions use the same schema/reply contract as server callbacks.
-spec request_tags([hls_source:form()]) -> {[atom()], [atom()]}.
request_tags(Forms) ->
    case xls_parse:find_optional_attribute(Forms, hls_phases) of
        none -> {[Tag || {Tag, _} <- groups(Forms, handle_call)],
            [Tag || {Tag, _} <- groups(Forms, handle_cast)]};
        {ok, Phases} ->
            Callbacks = xls_statem_callbacks:prepare(Forms, Phases),
            Tags = fun(Kind) -> lists:usort([xls_pattern_lower:record_pattern_name(Pattern)
                || {clause, _, [Pattern | _], _, _} <- maps:get(Kind, Callbacks)]) end,
            {Tags(call), Tags(cast)}
    end.

%% Require a unique call request with a nonempty, duplicate-free set of declared replies.
-spec declaration(term(), [atom()], #{atom() => [atom(), ...]}) -> #{atom() => [atom(), ...]}.
declaration({Request, Replies}, Public, Acc)
        when is_atom(Request), is_list(Replies), Replies =/= [] ->
    case maps:is_key(Request, Acc) of
        true -> error({duplicate_hls_reply_request, Request});
        false -> ok
    end,
    case length(lists:usort(Replies)) =:= length(Replies)
            andalso lists:all(fun(Tag) -> lists:member(Tag, Public) end, Replies) of
        true -> Acc#{Request => Replies};
        false -> error({invalid_hls_reply_records, Request, Replies})
    end;
declaration(Entry, _Public, _Acc) -> error({invalid_hls_reply_declaration, Entry}).

-doc "Groups call/cast clauses by request record, preserving clause order and the declared call arity.".
-spec groups([hls_source:form()], atom()) -> [{atom(), [erl_parse:abstract_clause()]}].
groups(Forms, Function) ->
    Arity = case Function of handle_call -> call_arity(Forms); _ -> 2 end,
    Clauses = clauses(Forms, Function, Arity),
    xls_callback_lower:group_by(Clauses, fun
        ({clause, _, [Pattern | _Arguments], _, _}) ->
            xls_pattern_lower:record_pattern_name(Pattern)
    end).

%% Embedded by hls_pack, so a deployed proxy needs neither source nor compiler
%% analysis. CPU-only modules without the transform retain the ordinary adapter.
-doc "Returns the embedded service contract, or none for an untransformed CPU-only module.".
-spec from_module(module()) -> {ok, contract()} | none.
from_module(Module) ->
    case proplists:get_value(hls_service_contract, Module:module_info(attributes)) of
        [Contract] -> {ok, Contract};
        undefined -> none
    end.

-doc "Selects handle_call/3 for bounded retained-reply servers; mixed call arities are rejected.".
-spec call_arity([hls_source:form()]) -> 2 | 3.
call_arity(Forms) ->
    Two = clauses(Forms, handle_call, 2),
    Three = clauses(Forms, handle_call, 3),
    case {Two, Three, xls_parse:find_optional_attribute(Forms, hls_pending_calls)} of
        {_, [], none} -> 2;
        {[], _, {ok, N}} when is_integer(N), N > 0, N =< 255 -> 3;
        _ -> error(invalid_hls_pending_calls)
    end.

%% Retained calls require an explicit finite resource and continuation vocabulary.
-spec extended([hls_source:form()], contract()) -> contract().
extended(Forms, Contract) ->
    case call_arity(Forms) of
        2 -> Contract;
        3 ->
            {ok, N} = xls_parse:find_optional_attribute(Forms, hls_pending_calls),
            Names = case xls_parse:find_optional_attribute(Forms, hls_continuations) of
                none -> [];
                {ok, Value} -> Value
            end,
            Contract#{pending_calls => N,
                continuations => hls_continuation:validate(Names)}
    end.

%% Callback families are optional; absence contributes no request tags.
-spec clauses([hls_source:form()], atom(), arity()) -> [erl_parse:abstract_clause()].
clauses(Forms, Name, Arity) ->
    lists:append([C || {function, _, F, A, C} <- Forms, F =:= Name, A =:= Arity]).
