# Retained replies and continuation steps

A bounded `hls_gs` server can accept a call now and reply after later input. Opt in with `-hls_pending_calls(N)` and implement `handle_call(Request, From, State)` instead of `handle_call/2`. `N` is 1–255. Declare each call's allowed reply records as usual in [service contracts](service-contracts.md).

`From` has type `hls_gs:from()`: save it in typed state and return it unchanged when completing the call. It belongs to one activation and is not a PID or wire transaction ID. A completed handle is never reissued in that activation; another reply to it is ignored. Caller timeout abandons interest, but keeps the service slot occupied until completion. Reset requires a coordinated transport/session reset; restarting a host proxy alone does not cancel device work.

## Bounded iteration

Declare finite names with `-hls_continuations([drain, ...])`. A callback may return `{noreply, State, {continue, drain}}`; `handle_continue(drain, State)` then executes before any later external request. Put iteration arguments and progress in typed state. Each step may finish one caller and schedule another step:

```erlang
{noreply, NextState, [{reply, SavedFrom, #result{value = Value}},
                     {continue, drain}]}
```

The action list contains at most one reply followed by at most one continuation. Either may be omitted; `{noreply, State}` finishes the step without either action. Ordinary `{reply, Reply, State}` and `{reply, Reply, State, {continue, Name}}` finish the current call immediately. Actions must have statically known list/tuple structure; their values may be computed. The same result forms execute on ERTS through `hls_gs`.

Output backpressure can suspend a step. Later input cannot overtake the continuation sequence, so do not use a continuation to await an external message: return plain `noreply` and resume from a later callback instead. An endless continuation sequence starves this server's external requests. Other servers and independently connected debug services can continue.

## State machines

`hls_statem` uses the same `From` type, capacity declaration and reply contract. Declare `-hls_reply_port(reply)` and include `reply` in `-hls_outputs(...)`; route it to the requesting host. Callbacks receive `Phase({call, From}, Request, Data)`. Call the CPU adapter with `hls_statem:call/2,3` or ordinary `gen_server` request functions. Hardware uses the generated service contract and existing fabric proxy. A synchronous request must target exactly one actor.

Consume the request and save `From` in typed data, or reply immediately:

```erlang
{waiting, NextData, consume, [{reply, From, #result{value = Value}}]}
```

Iteration uses OTP's [`{next_event, internal, Name}`](https://www.erlang.org/doc/apps/stdlib/gen_statem.html#t:action/0), with the same `-hls_continuations` declaration:

```erlang
{draining, NextData, consume,
 [{reply, SavedFrom, #result{value = Value}}, {next_event, internal, drain}]}
```

This invokes `draining(internal, drain, Data)`. Phase entry runs first, then the inserted event, then postponed retries and later input. An internal step creates no phase boundary unless it changes phase or returns `repeat_phase`. A reply precedes any resulting entry effects. The whole step waits if its reply cannot be accepted; callbacks without replies can still progress.

Ordinary cast/call and named internal callbacks may append at most one reply followed by one event to a consuming conclusion. Call callbacks cannot postpone or contribute to a reduction; retaining `From` after consuming the request is the supported way to wait. Entry and reduction-completion callbacks retain their existing result forms. This is a bounded subset of OTP actions: one statically named pending event, with arguments in application data.

## Capacity and failure

Applications hold reply handles in their own state. The runtime additionally records live caller ownership to reject duplicates, ignore stale completions and fail all waiting callers if the actor fails. This bounded table is a runtime policy, not a requirement of XLS. ERTS monitors provide failure notification independently of application state; hardware currently needs this ownership record. Retained calls consume one slot each. With all slots occupied, a new call receives `{error, {remote_error, busy}}` before its callback runs. Casts need no slot and can release existing calls. Reserve extra capacity if inspection calls must work while application storage is full.

Callback exceptions and valid-handle reply-contract violations terminate the CPU adapter. Hardware latches failure, emits an error for every outstanding call and rejects subsequent work until reset. Callback exceptions and invalid replies preserve the previous application state; an explicit `hls_statem` `fail` conclusion retains its returned diagnostic data. This retained-server policy prevents callers from being stranded by loss of callback state. It differs from the existing immediate server's [failure policy](control-flow.md). `hls_gs` reports failed casts on the reserved cast transaction ID; `hls_statem` reports failures to calls and exposes its latched actor failure through debug observation. No successful action from the failing step commits.

Codes 16, 17 and 18 mean `busy`, `reply_handle_exhausted` and `duplicate_transaction`. Handle exhaustion terminates the activation instead of wrapping. Duplicate live wire transaction IDs and calls using the reserved cast ID are protocol errors; normal fabric proxies prevent both.

Input and output routing must progress independently. Use the fabric ingress/egress modules; a request/reply-serializing adapter such as `hls_debug_route` cannot carry a service that needs later input to finish an earlier call.

## Cost and validation

Storage grows with the declared reply capacity and application state, not the number of replies in one drain. Draining trades that storage for serial callback steps and can delay later requests. The `hls_gs` generated driver requires at least two pipeline stages and initiation interval two; use `--pipeline-stages 2 --initiation-interval 2` with `tools/compile_xls.py`. Callback logic may require a slower schedule. Immediate `handle_call/2` servers and state machines without these declarations incur no added hardware. State-machine iteration adds eight private state bits. Retained calls additionally add `96 + 72*N` ownership bits per actor, plus application-held handles/data and reply logic. Shared actors store these private fields in their existing state RAM rows.

`rebar3 eunit` checks CPU ordering, bounded admission, abandoned callers, stale handles and failure. `bash tools/test_deferred_replies.sh XLS_ROOT` checks generated RTL at two schedules with long reply stalls, slot reuse, failure draining, reset and combinational-loop checks. `bash tools/test_statem_replies.sh XLS_ROOT` also checks internal-event priority and singleton/two-actor shared-RAM RTL at two pipeline depths. Complete D3 coverage remains in the existing CI jobs.
