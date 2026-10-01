-module(xls_scheduler_observation).
-moduledoc "Optional semantic observation output for completed scheduler metadata.".
-export([enabled/1, imports/1, proc_field/1, config_parameter/1, config_value/1,
    sample/1, arguments/1, names/1, spawn_argument/2, wires/1, ports/1]).

-doc "Validates and reads the optional observation flag.".
-spec enabled(map()) -> boolean().
enabled(Options) ->
    case maps:get(mailbox_debug, Options, false) of
        Flag when is_boolean(Flag) -> Flag;
        Other -> error({mailbox_debug, Other})
    end.

-doc "Lists static DSLX observation libraries required by the selected options.".
-spec imports(map()) -> [any()].
imports(Options) -> optional(Options, [scheduler_observation]).
-doc "Declares the optional observation output on a generated proc.".
-spec proc_field(map()) -> [any()].
proc_field(Options) -> optional(Options,
    "\n  mailbox_debug_out: chan<u24[ACTOR_COUNT]> out;\n").
-doc "Adds the optional observation endpoint to a proc's constructor.".
-spec config_parameter(map()) -> [any()].
config_parameter(Options) -> optional(Options,
    ",\n      mailbox_debug_out: chan<u24[ACTOR_COUNT]> out").
-doc "Retains the optional observation endpoint in proc configuration.".
-spec config_value(map()) -> [any()].
config_value(Options) -> optional(Options, "\n      mailbox_debug_out,\n").

%% Includes actors awaiting their own output slot in the public egress-wait flag.
-doc "Emits the passive per-actor mailbox snapshot, including occupied output reservations.".
-spec sample(map()) -> iodata().
sample(Options) -> optional(Options, """

    // The shell always accepts this diagnostic output. Query backpressure
    // stops at the shell's retained copy and never reaches this channel.
    // Observe the state entering this step: all prior-step RAM requests
    // and executor transfers have been accepted. No callback data is copied.
    let _observation = send(join(), mailbox_debug_out,
      scheduler_observation::snapshot(
        state.occupied, state.order, state.postponed, state.in_flight,
        state.mail_candidates, state.entry_probes,
        scheduler::exclude_reserved(state.egress_waiters, state.outbox_busy),
        state.egress_busy, state.phase as u2,
        state.completed_valid && state.completed.effects_valid,
        state.completed.slot));

""").

-doc "Declares or connects the observation channels required by the chosen options.".
-spec arguments(map()) -> [any()].
arguments(Spec = #{schedulers := Schedulers}) -> optional(Spec,
    [[Stem, "_mailbox_debug_out: chan<u24[u32:", integer_to_list(Slots), "]> out"]
        || #{stem := Stem, slot_count := Slots} <- Schedulers]).
-doc "Lists generated endpoints in the same order as their parameter declarations.".
-spec names(map()) -> [any()].
names(Spec = #{schedulers := Schedulers}) -> optional(Spec,
    [[Stem, "_mailbox_debug_out"] || #{stem := Stem} <- Schedulers]).
-doc "Passes the optional observation endpoint to one generated instance.".
-spec spawn_argument(map(),term()) -> [any()].
spawn_argument(Spec, Stem) -> optional(Spec, [",\n      ", Stem, "_mailbox_debug_out"]).

%% These aliases are private to the shell, not application/debug ingress.
%% XLS array packing places slot zero in the least significant word.
-doc "Declares wrapper wires for the selected observation ports.".
-spec wires(map()) -> [[[any()],...]].
wires(#{groups := Groups}) ->
    [["    wire [", integer_to_list(Slots*24-1), ":0] scheduler_", integer_to_list(I),
        "_mailbox_debug;\n    wire scheduler_", integer_to_list(I), "_mailbox_debug_vld;\n"]
        || {I, #{slot_count := Slots}} <- lists:enumerate(0, Groups)].
-doc "Connects wrapper observation ports with constant readiness.".
-spec ports(map()) -> [[[any()],...]].
ports(#{groups := Groups}) ->
    [[",\n        ._scheduler_", integer_to_list(I), "_mailbox_debug_out(scheduler_",
        integer_to_list(I), "_mailbox_debug),\n        ._scheduler_", integer_to_list(I),
        "_mailbox_debug_out_vld(scheduler_", integer_to_list(I), "_mailbox_debug_vld),\n",
        "        ._scheduler_", integer_to_list(I), "_mailbox_debug_out_rdy(1'b1)"]
        || {I, _} <- lists:enumerate(0, Groups)].

%% Includes generated text only when the observation option is enabled.
-spec optional(map(),[any()]) -> [any()].
optional(Options, Text) -> case enabled(Options) of true -> Text; false -> [] end.
