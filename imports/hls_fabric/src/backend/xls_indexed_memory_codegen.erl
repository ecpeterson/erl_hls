-module(xls_indexed_memory_codegen).
-moduledoc "Connects borrowed gather rows to shared execution through masked 1R1W storage.".
-export([optional/2, request_fields/1, loader_bindings/1, dispatch/2]).

-doc "Emits a physical gather fragment only when indexed storage is selected.".
-spec optional(map(), iodata()) -> iodata().
optional(Spec, Text) ->
    case maps:get(gather_collection, Spec, false) of true -> Text; false -> [] end.

-doc "Carries a frozen progress record and borrowed payload into the executor.".
-spec request_fields(map()) -> iodata().
request_fields(Spec) -> optional(Spec,
    "  gather_valid: bool,\n  gather_progress: GatherProgress,\n"
    "  gather_values: GatherValues,\n  gather_failure: hls_failure::Code,\n").

-doc "Supplies optional read ports, one checked row read and the response-ownership join.".
-spec loader_bindings(map()) -> [{binary(), iodata()}].
loader_bindings(Spec) ->
    [{<<"@@OPERAND_GATHER_FIELD@@">>, optional(Spec, "  gathered: GatherRamReadResp,\n")},
     {<<"@@OPERAND_GATHER_BIND@@">>, optional(Spec, "    let gathered = state.1.gathered;\n")},
     {<<"@@OPERAND_GATHER_VALUE@@">>, optional(Spec, "gathered,")},
     {<<"@@GATHER_MEMBERS@@">>, optional(Spec,
        "  gather_read_req_out: chan<GatherRamReadReq> out;\n"
        "  gather_read_resp_in: chan<GatherRamReadResp> in;\n")},
     {<<"@@GATHER_PARAMETERS@@">>, optional(Spec,
        ",\n      gather_read_req_out: chan<GatherRamReadReq> out,\n"
        "      gather_read_resp_in: chan<GatherRamReadResp> in")},
     {<<"@@GATHER_NAMES@@">>, optional(Spec,
        ", gather_read_req_out, gather_read_resp_in")},
     {<<"@@GATHER_READ@@">>, optional(Spec,
        "    let read_gather = send_if(tok, gather_read_req_out, valid && ticket.gather_valid,\n"
        "      indexed_gather_ram::read(ticket.slot * u32:2 + ticket.gather_lease.bank as u32));\n"
        "    let (gather_done, gathered) = recv_if(read_gather, gather_read_resp_in,\n"
        "      valid && ticket.gather_valid, zero!<GatherRamReadResp>());\n")},
     {<<"@@GATHER_FIELDS@@">>, optional(Spec,
        "      gather_valid: ticket.gather_valid,\n"
        "      gather_progress: ticket.gather_progress,\n"
        "      gather_values: gathered.data,\n"
        "      gather_failure: ticket.gather_failure,\n")},
     {<<"@@GATHER_JOIN@@">>, optional(Spec, ", gather_done")}].

-doc "Consumes a borrowed complete view, or delivers a checked protocol failure before ordinary dispatch.".
-spec dispatch(map(), iodata()) -> iodata().
dispatch(Spec, Ordinary) ->
    case maps:get(gather_collection, Spec, false) of
        false -> Ordinary;
        true -> [
            "  let dispatched = if hls_failure::failed(request.gather_failure) {\n",
            "    ActorDispatch { machine: ActorState { failure: hls_failure::first(\n",
            "      machine.failure, request.gather_failure), ..machine },\n",
            "      dispatched: true, directive: Directive::FAIL, ..zero!<ActorDispatch>() }\n",
            "  } else if request.gather_valid {\n",
            "    shared_machine_complete_gather(machine, request.gather_progress, request.gather_values)\n",
            "  } else {\n", Ordinary, "    dispatched\n  };\n"
        ]
    end.
