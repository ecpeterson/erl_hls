-module(hls_static_term).
-moduledoc """
Recognizes process-free Erlang data used by deterministic semantic identities.

Atoms, numbers, binaries, lists, tuples and maps remain ordinary static values. PIDs, ports,
references and functions identify live VM state and are rejected wherever they occur recursively.
""".

-export([validate/1]).
-export_type([live_kind/0]).

-doc "Kind of live VM value excluded from a process-free identity.".
-type live_kind() :: pid | port | reference | function.

-doc "Checks recursively that a term contains no PID, port, reference or function.".
-spec validate(term()) -> ok | {error, live_kind()}.
validate(Term) ->
    case live_value(Term) of
        none -> ok;
        Kind -> {error, Kind}
    end.

%% Return the first kind of live value in deterministic traversal order.
-spec live_value(term()) -> none | live_kind().
live_value(Term) when is_pid(Term) -> pid;
live_value(Term) when is_port(Term) -> port;
live_value(Term) when is_reference(Term) -> reference;
live_value(Term) when is_function(Term) -> function;
live_value([Head | Tail]) ->
    first_live([Head, Tail]);
live_value(Term) when is_tuple(Term) -> first_live(tuple_to_list(Term));
live_value(Term) when is_map(Term) ->
    first_live(lists:append([[Key, Value] || {Key, Value} <- maps:to_list(Term)]));
live_value(_Term) ->
    none.

%% Scan one sequence without accepting a live value hidden in an improper-list tail.
-spec first_live([term()]) -> none | live_kind().
first_live([]) ->
    none;
first_live([Term | Rest]) ->
    case live_value(Term) of
        none -> first_live(Rest);
        Kind -> Kind
    end.
