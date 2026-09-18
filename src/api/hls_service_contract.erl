%%%% One source of truth for hls_gs request kinds and allowed reply records.
-module(hls_service_contract).
-moduledoc false.

-export([from_forms/1, from_module/1, groups/2]).
-export_type([contract/0]).

-doc "Allowed reply tags by call request, plus supported cast tags.".
-type contract() :: #{calls := #{atom() => [atom(), ...]}, casts := [atom()]}.

-doc "Validates request/reply declarations and returns allowed call replies and cast tags.".
-spec from_forms([hls_source:form()]) -> contract().
from_forms(Forms) ->
    Public = xls_parse:find_tags(Forms),
    Calls = [Tag || {Tag, _} <- groups(Forms, handle_call)],
    Casts = [Tag || {Tag, _} <- groups(Forms, handle_cast)],
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
        {[], []} -> #{calls => Replies, casts => Casts};
        {Missing, Extra} -> error({hls_reply_requests, #{missing => Missing, extra => Extra}})
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

-doc "Groups two-argument callback clauses by request record, preserving clause order.".
-spec groups([hls_source:form()], atom()) -> [{atom(), [erl_parse:abstract_clause()]}].
groups(Forms, Function) ->
    Clauses = xls_parse:find_function(Forms, Function, 2),
    xls_callback_lower:group_by(Clauses, fun
        ({clause, _, [Pattern, _State], _, _}) ->
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
