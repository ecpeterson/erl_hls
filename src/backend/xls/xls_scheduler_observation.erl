-module(xls_scheduler_observation).
-moduledoc "Optional semantic observation output for completed scheduler metadata.".
-export([enabled/1, imports/1, proc_field/1, config_parameter/1, config_value/1,
    sample/1, arguments/1, names/1, spawn_argument/2, wires/1, ports/1]).

enabled(Options) ->
    case maps:get(mailbox_debug, Options, false) of
        Flag when is_boolean(Flag) -> Flag;
        Other -> error({mailbox_debug, Other})
    end.

imports(Options) -> optional(Options, [scheduler_observation]).
proc_field(Options) -> optional(Options,
    "\n  mailbox_debug_out: chan<u24[ACTOR_COUNT]> out;\n").
config_parameter(Options) -> optional(Options,
    ",\n      mailbox_debug_out: chan<u24[ACTOR_COUNT]> out").
config_value(Options) -> optional(Options, "\n      mailbox_debug_out,\n").

sample(Options) -> optional(Options, """

    // The shell always accepts this diagnostic output. Query backpressure
    // stops at the shell's retained copy and never reaches this channel.
    // Observe the state entering this step: all prior-step RAM requests
    // and executor transfers have been accepted. No callback data is copied.
    let _observation = send(join(), mailbox_debug_out,
      scheduler_observation::snapshot(
        state.occupied, state.order, state.postponed, state.in_flight,
        state.mail_candidates, state.entry_probes, state.egress_waiters,
        state.egress_busy, state.phase as u2,
        state.completed_valid && state.completed.effects_valid,
        state.completed.slot));

""").

arguments(Spec = #{schedulers := Schedulers}) -> optional(Spec,
    [[Stem, "_mailbox_debug_out: chan<u24[u32:", integer_to_list(Slots), "]> out"]
        || #{stem := Stem, slot_count := Slots} <- Schedulers]).
names(Spec = #{schedulers := Schedulers}) -> optional(Spec,
    [[Stem, "_mailbox_debug_out"] || #{stem := Stem} <- Schedulers]).
spawn_argument(Spec, Stem) -> optional(Spec, [",\n      ", Stem, "_mailbox_debug_out"]).

%% These aliases are private to the shell, not application/debug ingress.
%% XLS array packing places slot zero in the least significant word.
wires(#{groups := Groups}) ->
    [["    wire [", integer_to_list(Slots*24-1), ":0] scheduler_", integer_to_list(I),
        "_mailbox_debug;\n    wire scheduler_", integer_to_list(I), "_mailbox_debug_vld;\n"]
        || {I, #{slot_count := Slots}} <- lists:enumerate(0, Groups)].
ports(#{groups := Groups}) ->
    [[",\n        ._scheduler_", integer_to_list(I), "_mailbox_debug_out(scheduler_",
        integer_to_list(I), "_mailbox_debug),\n        ._scheduler_", integer_to_list(I),
        "_mailbox_debug_out_vld(scheduler_", integer_to_list(I), "_mailbox_debug_vld),\n",
        "        ._scheduler_", integer_to_list(I), "_mailbox_debug_out_rdy(1'b1)"]
        || {I, _} <- lists:enumerate(0, Groups)].

optional(Options, Text) -> case enabled(Options) of true -> Text; false -> [] end.
