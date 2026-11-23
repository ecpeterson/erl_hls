%% Only this call graph and its record types belong to the hardware closure.
-spec hardware_value(hls_nums:u32()) -> hls_nums:u32().
hardware_value(Value) ->
    Input = ?INPUT(Value),
    ?MODULE:sample_value(#closure_sample{inner = #closure_inner{value = Input}}).

-doc "Returns a nested record value through the local size helper.".
-spec sample_value(#closure_sample{}) -> hls_nums:u32().
sample_value(#closure_sample{inner = Inner}) ->
    ?MODULE:bit_size(bit_size(Inner#closure_inner.value)).

-doc "Adds one; both local and self-qualified calls must avoid the size BIF.".
-spec bit_size(hls_nums:u32()) -> hls_nums:u32().
bit_size(Value) -> Value + 1.

%% Every optional host function is after the fixed hardware source locations.
-ifdef(HOST_COMPARISON).
-doc "Compares unlike Erlang terms using the host total ordering.".
-spec host_comparison() -> boolean().
host_comparison() -> 1 < false.
-endif.

-ifdef(HOST_BINARY).
%% Native byte order is valid host syntax but unsupported in hardware.
-spec host_binary(hls_nums:u32()) -> hls_bits:bits(32).
host_binary(Value) -> <<Value:32/native>>.
-endif.

-ifdef(HOST_RECURSION).
%% This ordinary recursive host function has no finite hardware helper graph.
-spec host_recursion(hls_nums:u32()) -> hls_nums:u32().
host_recursion(Value) -> host_recursion(Value).
-endif.

-ifdef(HOST_PROVIDER).
%% An unused provider call must not invoke companion-discovery callbacks.
-spec host_provider(hls_nums:u32()) -> hls_nums:u32().
host_provider(Value) -> xls_hardware_source_closure_tests:identity(Value).
-endif.

-ifdef(HOST_TYPE).
%% Host-only provider types must not declare hardware companion dependencies.
%% Only the host record refers to this local type alias.
-type host_only_value() :: xls_hardware_source_closure_tests:host_value().
-record(host_only_record, {value = undefined :: host_only_value()}).
%% Construct a host value without requesting a hardware layout.
-spec host_record() -> #host_only_record{}.
host_record() -> #host_only_record{value = 1}.
-endif.

-ifdef(HOST_REDUCTION).
%% An ordinary host tuple cannot designate a hardware reduction accumulator.
-record(host_leaf, {owner = self() :: pid()}).
-record(host_accumulator, {value = #host_leaf{} :: #host_leaf{}}).
-doc "Returns ordinary host data with a nested process identifier, not a hardware reduction action.".
-spec host_reduction() -> tuple().
host_reduction() ->
    {open_reduction, host_sum, 1, [], {commutative_monoid, #host_accumulator{}}}.
-endif.
