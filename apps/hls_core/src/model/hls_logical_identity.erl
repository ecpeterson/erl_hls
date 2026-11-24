-module(hls_logical_identity).
-moduledoc """
Defines source-level logical names independently of Erlang processes, runtime
incarnations, placement indices, and transport addresses.

The accepted domain deliberately matches the original topology contract:
atoms, every Erlang integer (including negative integers), and nonempty tuples
whose elements recursively belong to the same domain. Validation reports the
first invalid nested value.
""".

%% Logical identity validation.
-export([is_valid/1, validate/1]).
%% Shared logical identity contracts.
-export_type([destination/0, id/0]).

-doc "A recursive source-level name; integers are not restricted to nonnegative values.".
-type id() :: atom() | integer() | tuple().

-doc "A logical actor or declared external recipient, not a process or transport endpoint.".
-type destination() :: {actor, id()} | {external, id()}.

-doc "Returns whether `Value` belongs to the recursive logical-identity domain.".
-spec is_valid(term()) -> boolean().
is_valid(Value) when is_atom(Value); is_integer(Value) ->
    true;
is_valid(Value) when is_tuple(Value), tuple_size(Value) > 0 ->
    lists:all(fun is_valid/1, tuple_to_list(Value));
is_valid(_Value) ->
    false.

-doc "Accepts one logical identity or raises `{invalid_topology_id, Value}` for the first invalid nested value.".
-spec validate(term()) -> ok.
validate(Value) when is_atom(Value); is_integer(Value) ->
    ok;
validate(Value) when is_tuple(Value), tuple_size(Value) > 0 ->
    lists:foreach(fun validate/1, tuple_to_list(Value));
validate(Value) ->
    error({invalid_topology_id, Value}).
