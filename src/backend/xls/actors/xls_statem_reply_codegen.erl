-module(xls_statem_reply_codegen).
-moduledoc "Renders immediate or retained reply ownership and the single reply effect for common actors. xls_statem_lower supplies the checked reply strategy; common actor and execution renderers use these fragments for admission, completion and packed state. This is actor-local reply bookkeeping, not host transport or session ownership.".
%% Inspect optional caller storage and reserve its effect layout.
-export([enabled/1, width/1, count/1, layout/1]).
%% Render caller-book declarations, initialization and operations.
-export([optional/2, declarations/1, functions/1, initial/1]).
%% Integrate admission, callback completion and reply publication.
-export([admit/3, finish/2, effect/1]).

-doc "Reports whether an actor requires the common reply path.".
-spec enabled(map()) -> boolean().
enabled(Spec) -> maps:get(retained_calls, Spec, none) =/= none.

-doc "Emits a fragment only when caller ownership is present.".
-spec optional(map(), xls_dslx:value()) -> xls_dslx:value().
optional(Spec, Code) ->
    case enabled(Spec) of
        true -> Code;
        false -> []
    end.

-doc "Returns the actor-local caller book's packed width.".
-spec width(map()) -> non_neg_integer().
width(Spec) ->
    case mode(Spec) of
        immediate -> 32;
        retained -> 96 + 72 * count(Spec);
        none -> 0
    end.

-doc "Returns the statically bounded number of retained callers.".
-spec count(map()) -> pos_integer().
count(#{retained_calls := #{pending_calls := N}}) -> N.

-doc "Reserves one effect layout after all ordinary entry variants.".
-spec layout(map()) -> non_neg_integer().
layout(#{entries := Entries}) ->
    N = lists:sum([length(maps:get(layouts, Entry)) || Entry <- Entries]),
    case N < 256 of
        true -> N;
        false -> error(too_many_hls_statem_reply_layouts)
    end.

-doc "Declares the private caller-book type used by the machine codec.".
-spec declarations(map()) -> xls_dslx:value().
declarations(#{retained_calls := #{mode := immediate}}) ->
    "type ReplyBook = hls_reply::Immediate;\n\n";
declarations(Spec) ->
    case enabled(Spec) of
        false ->
            [];
        true ->
            [
                "const REPLY_CAPACITY = u32:",
                integer_to_list(count(Spec)),
                ";\ntype ReplyBook = hls_reply::Book<REPLY_CAPACITY>;\n\n"
            ]
    end.

-doc "Initializes failure status and, for retained calls, nonzero handle allocation.".
-spec initial(map()) -> xls_dslx:value().
initial(#{retained_calls := #{mode := immediate}}) ->
    "  replies: zero!<ReplyBook>(),\n";
initial(Spec) ->
    case enabled(Spec) of
        false -> [];
        true -> ["  replies: hls_reply::initial<u32:", integer_to_list(count(Spec)), ">(),\n"]
    end.

-doc "Allocates only for a declared call whose mailbox callback can run.".
-spec admit(map(), xls_dslx:value(), xls_dslx:value()) -> xls_dslx:value().
admit(Spec, Frame, Valid) ->
    optional(Spec, [
        "    let (admitted_replies, call_from, call_error) = if ",
        Valid,
        " && request_error(",
        Frame,
        ") != u32:0 { (machine.replies, u64:0, request_error(",
        Frame,
        ")) } else if ",
        Valid,
        " && is_call(",
        Frame,
        ".header.op) { hls_reply::",
        case mode(Spec) of
            immediate -> "immediate_admit";
            _ -> "admit"
        end,
        "(machine.replies, ",
        Frame,
        ") } else { (machine.replies, u64:0, u32:0) };\n"
    ]).

-doc "Validates the final scheduling outcome before completing or exposing any caller reply.".
-spec finish(map(), xls_dslx:value()) -> xls_dslx:value().
finish(Spec, Frame) ->
    optional(Spec, [
        "    let (reply_book, response, response_valid) = finish_reply(admitted_replies, ",
        Frame,
        ", call_error, reply_from, reply_frame, reply_allowed, failure);\n"
    ]).

-doc "Emits call classification, reply-contract checks and rejected-call completion.".
-spec functions(map()) -> xls_dslx:value().
functions(Spec = #{retained_calls := #{calls := Calls}}) ->
    [
        request_validation(Spec),
        "fn is_call(tag: u8) -> bool { false",
        [
            [" || tag == Tag::", xls_names:enum_member(T), " as u8"]
         || T <- maps:keys(Calls)
        ],
        " }\n",
        "fn reply_allowed(from: u64, tag: u8) -> bool { ",
        lists:join(" || ", [
            "false"
            | [
                [
                    "((from as u8) == Tag::",
                    xls_names:enum_member(T),
                    " as u8 && (",
                    lists:join(" || ", [
                        ["tag == Tag::", xls_names:enum_member(R), " as u8"]
                     || R <- Rs
                    ]),
                    "))"
                ]
             || {T, Rs} <- maps:to_list(Calls)
            ]
        ]),
        " }\n",
        completion_functions(Spec)
    ];
functions(_Spec) ->
    [].

%% Both ownership modes expose the same operations to execution renderers.
-spec completion_functions(map()) -> xls_dslx:value().
completion_functions(#{retained_calls := #{mode := immediate}}) ->
    """
    fn complete_reply(book: ReplyBook, from: u64, reply: axis::Frame,
        allowed: bool, failure: u32) -> (ReplyBook, axis::Frame, bool) {
      hls_reply::immediate_complete(book, from, reply, allowed, failure)
    }
    fn finish_reply(book: ReplyBook, input: axis::Frame, admission_error: u32, from: u64,
        reply: axis::Frame, allowed: bool, failure: hls_failure::Code) -> (ReplyBook, axis::Frame, bool) {
      let (next, response, valid) = complete_reply(book, from, reply, allowed, failure as u32);
      if admission_error != u32:0 {
        (book, hls_reply::error_frame(input.header.txid, admission_error), true)
      } else if next.failure != u32:0 {
        (next, hls_reply::error_frame(input.header.txid, next.failure), true)
      } else { (next, response, valid) }
    }
    fn actor_reply_failure(machine: ActorState, frame: axis::Frame, received: bool) -> ActorDispatch {
      let failure = if machine.replies.failure != u32:0 { machine.replies.failure }
        else { hls_failure::source_error(machine.failure) };
      ActorDispatch { machine, reply: hls_reply::error_frame(frame.header.txid, failure),
        reply_valid: received, dispatched: received, directive: Directive::CONSUME,
        ..zero!<ActorDispatch>() }
    }

    """;
completion_functions(Spec) ->
    [
        "fn complete_reply(book: ReplyBook, from: u64, reply: axis::Frame, allowed: bool, failure: u32) -> (ReplyBook, axis::Frame, bool) {\n",
        "  let (next, response, valid) = hls_reply::complete(book, from, reply, allowed, failure);\n",
        "  if ",
        server_notice(Spec),
        " && next.failure != u32:0 { (next, hls_reply::error_frame(u8:255, next.failure), true) } else { (next, response, valid) }\n}\n",
        "fn finish_reply(book: ReplyBook, input: axis::Frame, admission_error: u32, from: u64,\n",
        "    reply: axis::Frame, allowed: bool, failure: hls_failure::Code) -> (ReplyBook, axis::Frame, bool) {\n",
        "  if admission_error != u32:0 {\n",
        "    let duplicate = for (i, found): (u32, bool) in u32:0..u32:",
        integer_to_list(count(Spec)),
        " {\n",
        "      found || (book.slots[i].handle != u64:0 && book.slots[i].txid == input.header.txid)\n",
        "    }(false);\n",
        "    (book, hls_reply::error_frame(input.header.txid, admission_error), !duplicate)\n",
        "  } else {\n    let (next, response, valid) = hls_reply::complete(book, from, reply, allowed, failure as u32);\n",
        "    if ",
        server_notice(Spec),
        " && next.failure != u32:0 && !is_call(input.header.op) {\n",
        "      (next, hls_reply::error_frame(input.header.txid, next.failure), true)\n",
        "    } else { (next, response, valid) }\n  }\n",
        "}\n\n",
        "fn actor_reply_failure(machine: ActorState, frame: axis::Frame, received: bool) -> ActorDispatch {\n",
        "  let failed = ReplyBook { failure: if machine.replies.failure != u32:0 { machine.replies.failure } else { hls_failure::source_error(machine.failure) }, ..machine.replies };\n",
        "  let (replies, owned_reply, owned) = hls_reply::drain(failed);\n",
        "  ActorDispatch { machine: ActorState { replies, next_event: u8:0, enter_pending: false, ..machine },\n",
        "    reply: if owned { owned_reply } else { hls_reply::error_frame(frame.header.txid, failed.failure) },\n",
        "    reply_valid: owned || (received && (",
        server_notice(Spec),
        " || is_call(frame.header.op))), dispatched: received && !owned, directive: Directive::CONSUME, ..zero!<ActorDispatch>() }\n",
        "}\n\n"
    ].

%% Immediate calls carry their origin only within the callback, never between steps.
-spec mode(map()) -> none | immediate | retained.
mode(#{retained_calls := #{mode := immediate}}) ->
    immediate;
mode(Spec) ->
    case enabled(Spec) of
        true -> retained;
        false -> none
    end.

-doc "Forms the ordinary one-frame effect from a checked reply.".
-spec effect(map()) -> xls_dslx:value().
effect(Spec) ->
    [
        "EntryEffects { layout: u8:",
        integer_to_list(layout(Spec)),
        ", payloads: axis::bits_from_frame(dispatched.reply) as bits[ENTRY_EFFECT_PAYLOAD_BITS] }"
    ].

%% Server wire rejections precede callback ownership and do not fail the actor.
-spec request_validation(map()) -> xls_dslx:value().
request_validation(#{
    source_kind := server,
    retained_calls := #{calls := Calls, casts := Casts},
    message_words := Words
}) ->
    [
        "fn request_error(frame: axis::Frame) -> u32 {\n  match frame.header.op as Tag {\n",
        [
            [
                "    Tag::",
                xls_names:enum_member(Tag),
                " => if frame.header.payload_words == u8:",
                integer_to_list(maps:get(Tag, Words)),
                " { u32:0 } else { u32:3 },\n"
            ]
         || Tag <- lists:usort(maps:keys(Calls) ++ Casts)
        ],
        "    _ => u32:1,\n  }\n}\n"
    ];
request_validation(_) ->
    "fn request_error(frame: axis::Frame) -> u32 { u32:0 }\n".

%% Server proxies require one fault notice even when the failing step has no caller.
-spec server_notice(map()) -> string().
server_notice(#{source_kind := server}) -> "true";
server_notice(_) -> "false".
