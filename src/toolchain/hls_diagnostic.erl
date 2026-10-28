-module(hls_diagnostic).
-moduledoc "Owned compiler failures with stage, stable code and structured context. Context enrichment never reclassifies unexpected exceptions.".
-export([raise/4, with_context/2, format/1, json/1, json_value/1]).
-export_type([diagnostic/0, context/0, json_value/0]).

-doc "Additional owner-defined evidence, such as source, location, actor, role, option or limits; values retain their Erlang structure.".
-type context() :: #{atom() | binary() => term()}.
-doc "An expected failure identified by its owning stage and stable code, with human text and diagnostic evidence.".
-type diagnostic() :: #{stage := atom(), code := atom(), message := binary(), context := context()}.
-doc "JSON data after explicit conversion of Erlang terms; all object keys are UTF-8 binaries.".
-type json_value() :: null | boolean() | number() | binary() | [json_value()] |
    #{binary() => json_value()}.

-doc "Raises an owned error as {hls_diagnostic, Diagnostic}. Message is UTF-8 text; context retains values rather than formatting them into strings.".
-spec raise(atom(), atom(), binary(), context()) -> no_return().
raise(Stage, Code, Message, Context) ->
    error({hls_diagnostic, #{stage => Stage, code => Code, message => Message, context => Context}}).

-doc "Adds context defaults only to tagged errors from Fun. Inner context wins duplicate keys; the original error stack and unrelated exceptions are preserved. No process state is changed.".
-spec with_context(context(), fun(() -> Result)) -> Result.
with_context(Context, Fun) ->
    try Fun()
    catch error:{hls_diagnostic, #{context := Inner} = Diagnostic}:Stack ->
        erlang:raise(error, {hls_diagnostic, Diagnostic#{context := maps:merge(Context, Inner)}}, Stack)
    end.

-doc "Formats an owned failure for a terminal, including each context value in Erlang notation.".
-spec format(diagnostic()) -> iodata().
format(#{stage := Stage, code := Code, message := Message, context := Context}) ->
    unicode:characters_to_binary([io_lib:format("~p/~p: ~ts", [Stage, Code, Message]),
        [io_lib:format("~n  ~tp: ~tp", [Key, Value]) || {Key, Value} <- lists:sort(maps:to_list(Context))]]).

-doc "Encodes one diagnostic as JSON using json_value/1's explicit Erlang-term representation.".
-spec json(diagnostic()) -> binary().
json(Diagnostic) -> iolist_to_binary(json:encode(json_value(Diagnostic))).

-doc "Converts arbitrary evidence to JSON. Numbers and UTF-8 binaries remain scalars; every proper list remains an array. Text owners must supply binaries rather than character lists. Tuples use $tuple, maps with non-text or colliding keys use $map pairs (atom keys use $atom), and non-UTF-8 binaries use $binary_hex. Other runtime terms use $term with Erlang notation. Empty lists remain arrays; no term is evaluated.".
-spec json_value(term()) -> json_value().
json_value(Value) when is_number(Value) -> Value;
json_value(Value) when is_binary(Value) ->
    case unicode:characters_to_binary(Value) of
        Value -> Value;
        _ -> #{<<"$binary_hex">> => binary:encode_hex(Value, lowercase)}
    end;
json_value(Value) when Value =:= true; Value =:= false; Value =:= null -> Value;
json_value(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
json_value(Value) when is_tuple(Value) ->
    #{<<"$tuple">> => [json_value(Item) || Item <- tuple_to_list(Value)]};
json_value(Value) when is_map(Value) -> json_map(maps:to_list(Value));
json_value([]) -> [];
json_value([_ | _] = Value) ->
    case proper_list(Value) of
        true -> [json_value(Item) || Item <- Value];
        false -> printed_term(Value)
    end;
json_value(Value) -> printed_term(Value).

%% Text keys are convenient only when conversion cannot merge distinct Erlang keys.
-spec json_map([{term(), term()}]) -> json_value().
json_map(Pairs) ->
    Keys = [json_key(Key) || {Key, _} <- Pairs],
    case not lists:member(error, Keys) andalso length(lists:usort(Keys)) =:= length(Keys) of
        true -> maps:from_list([{Key, json_value(Value)}
            || {{ok, Key}, {_, Value}} <- lists:zip(Keys, Pairs)]);
        false -> #{<<"$map">> => [[pair_key(Key), json_value(Value)] || {Key, Value} <- Pairs]}
    end.

%% Compound map keys retain atom identity recursively, including map values inside a key.
-spec pair_key(term()) -> json_value().
pair_key(Key) when is_atom(Key) -> #{<<"$atom">> => atom_to_binary(Key, utf8)};
pair_key(Key) when is_tuple(Key) -> #{<<"$tuple">> => [pair_key(Item) || Item <- tuple_to_list(Key)]};
pair_key(Key) when is_map(Key) ->
    #{<<"$map">> => [[pair_key(K), pair_key(V)] || {K, V} <- maps:to_list(Key)]};
pair_key([]) -> [];
pair_key([_ | _] = Key) ->
    case proper_list(Key) of
        true -> [pair_key(Item) || Item <- Key];
        false -> printed_term(Key)
    end;
pair_key(Key) -> json_value(Key).

%% Object keys use text only; compound keys retain their shape through $map pairs.
-spec json_key(term()) -> {ok, binary()} | error.
json_key(Key) when is_atom(Key) -> {ok, atom_to_binary(Key, utf8)};
json_key(Key) when is_binary(Key) ->
    case unicode:characters_to_binary(Key) of Key -> {ok, Key}; _ -> error end;
json_key(_) -> error.

%% Guard list traversal without rejecting opaque improper-list context values.
-spec proper_list(term()) -> boolean().
proper_list([]) -> true;
proper_list([_ | Rest]) -> proper_list(Rest);
proper_list(_) -> false.

%% Runtime-only values have explicit textual representation rather than ambiguous JSON scalars.
-spec printed_term(term()) -> json_value().
printed_term(Value) -> #{<<"$term">> => unicode:characters_to_binary(io_lib:format("~0tp", [Value]))}.
