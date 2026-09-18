-module(xls_statem_reply_codegen).
-moduledoc "Caller ownership and a single reply effect for retained-call state machines.".
-export([optional/2, enabled/1, width/1, count/1, layout/1, declarations/1,
    admit/2, finish/2, functions/1, effect/1, initial/1]).

-doc "Reports whether an actor declares retained calls.".
-spec enabled(map()) -> boolean().
enabled(Spec) -> maps:get(retained_calls, Spec, none) =/= none.

-doc "Emits a fragment only when caller ownership is present.".
-spec optional(map(), iodata()) -> iodata().
optional(Spec, Code) -> case enabled(Spec) of true -> Code; false -> [] end.

-doc "Returns the actor-local caller book's packed RAM width.".
-spec width(map()) -> non_neg_integer().
width(Spec) -> case enabled(Spec) of true -> 96 + 72 * count(Spec); false -> 0 end.

-doc "Returns the statically bounded number of retained callers.".
-spec count(map()) -> pos_integer().
count(#{retained_calls := #{pending_calls := N}}) -> N.

-doc "Reserves one effect layout after all ordinary entry variants.".
-spec layout(map()) -> non_neg_integer().
layout(#{entries := Entries}) ->
    N = lists:sum([length(maps:get(layouts, Entry)) || Entry <- Entries]),
    case N < 256 of true -> N; false -> error(too_many_hls_statem_reply_layouts) end.

-doc "Declares the private caller-book type used by the machine codec.".
-spec declarations(map()) -> iodata().
declarations(Spec) -> case enabled(Spec) of
    false -> [];
    true -> ["const REPLY_CAPACITY = u32:", integer_to_list(count(Spec)), ";\ntype ReplyBook = hls_reply::Book<REPLY_CAPACITY>;\n\n"]
end.

-doc "Initializes nonzero handle allocation before any input is dispatched.".
-spec initial(map()) -> iodata().
initial(Spec) -> case enabled(Spec) of
    false -> [];
    true -> ["  replies: hls_reply::initial<u32:", integer_to_list(count(Spec)), ">(),\n"]
end.

-doc "Allocates only for a declared call whose mailbox callback can run.".
-spec admit(map(), direct | shared) -> iodata().
admit(Spec, Kind) ->
    {Frame, Valid} = case Kind of direct -> {"selected_frame", "dispatchable"}; shared -> {"frame", "tag_ok"} end,
    optional(Spec, ["    let (admitted_replies, call_from, call_error) = if ", Valid,
        " && is_call(", Frame, ".header.op) { hls_reply::admit(machine.replies, ", Frame,
        ") } else { (machine.replies, u64:0, u32:0) };\n"]).

-doc "Validates the final scheduling outcome before completing or exposing any caller reply.".
-spec finish(map(), direct | shared) -> iodata().
finish(Spec, Kind) ->
    Frame = case Kind of direct -> "selected_frame"; shared -> "frame" end,
    optional(Spec, ["    let (reply_book, response, response_valid) = finish_reply(admitted_replies, ", Frame,
        ", call_error, reply_from, reply_frame, reply_allowed, failure);\n"]).

-doc "Emits call classification, reply-contract checks and rejected-call completion.".
-spec functions(map()) -> iodata().
functions(Spec = #{retained_calls := #{calls := Calls}}) ->
    ["fn is_call(tag: u8) -> bool { ", lists:join(" || ", [["tag == Tag::", xls_names:enum_member(T), " as u8"] || T <- maps:keys(Calls)]), " }\n",
     "fn reply_allowed(from: u64, tag: u8) -> bool { ",
     lists:join(" || ", [["((from as u8) == Tag::", xls_names:enum_member(T), " as u8 && (",
        lists:join(" || ", [["tag == Tag::", xls_names:enum_member(R), " as u8"] || R <- Rs]), "))"] || {T, Rs} <- maps:to_list(Calls)]), " }\n",
     "fn finish_reply(book: ReplyBook, input: axis::Frame, admission_error: u32, from: u64,\n",
     "    reply: axis::Frame, allowed: bool, failure: hls_failure::Code) -> (ReplyBook, axis::Frame, bool) {\n",
     "  if admission_error != u32:0 {\n",
     "    let duplicate = for (i, found): (u32, bool) in u32:0..u32:", integer_to_list(count(Spec)), " {\n",
     "      found || (book.slots[i].handle != u64:0 && book.slots[i].txid == input.header.txid)\n",
     "    }(false);\n",
     "    (book, hls_reply::error_frame(input.header.txid, admission_error), !duplicate)\n",
     "  } else { hls_reply::complete(book, from, reply, allowed, hls_failure::kind(failure) as u32) }\n",
     "}\n\n",
     "fn shared_machine_reply_failure(machine: SharedMachine, frame: axis::Frame, received: bool) -> SharedDispatch {\n",
     "  let failed = ReplyBook { failure: if machine.replies.failure != u32:0 { machine.replies.failure } else { hls_failure::kind(machine.failure) as u32 }, ..machine.replies };\n",
     "  let (replies, owned_reply, owned) = hls_reply::drain(failed);\n",
     "  SharedDispatch { machine: SharedMachine { replies, next_event: u8:0, enter_pending: false, ..machine },\n",
     "    reply: if owned { owned_reply } else { hls_reply::error_frame(frame.header.txid, failed.failure) },\n",
     "    reply_valid: owned || (received && is_call(frame.header.op)), dispatched: received && !owned, directive: Directive::CONSUME, ..zero!<SharedDispatch>() }\n",
     "}\n\n"];

functions(_Spec) -> [].

-doc "Forms the scheduler's ordinary one-frame effect from a checked reply.".
-spec effect(map()) -> iodata().
effect(Spec) -> ["EntryEffects { layout: u8:", integer_to_list(layout(Spec)),
    ", payloads: axis::bits_from_frame(dispatched.reply) as bits[ENTRY_EFFECT_PAYLOAD_BITS] }"] .
