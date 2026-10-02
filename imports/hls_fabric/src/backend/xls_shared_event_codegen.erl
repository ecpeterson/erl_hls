-module(xls_shared_event_codegen).
-moduledoc false.
-export([shared_dispatch/1]).


-doc "Selects a named internal step before ordinary mailbox dispatch, after entry.".
-spec shared_dispatch(map()) -> iodata().
shared_dispatch(Spec = #{reductions := Reduction, shared_service := Mode}) ->
    Ordinary = xls_shared_reduction_service_codegen:shared_executor_dispatch(Reduction, Mode),
    Selected = case maps:get(continuations, Spec, []) =/= [] orelse xls_statem_reply_codegen:enabled(Spec) of
        false -> Ordinary;
        true -> ["  let dispatched = ",
              xls_statem_reply_codegen:optional(Spec, "if hls_failure::failed(machine.failure) { actor_reply_failure(machine, request.frame, request.received) } else "),
              "if !hls_failure::failed(machine.failure) &&\n",
              "      !machine.enter_pending && machine.next_event != u8:0 {\n",
              "    actor_next_event(machine)\n  } else {\n", Ordinary,
              "    dispatched\n  };\n"]
    end,
    xls_indexed_memory_codegen:dispatch(Spec,
        xls_shared_gather_codegen:shared_dispatch(Spec, Selected)).
