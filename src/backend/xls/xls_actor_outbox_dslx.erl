-module(xls_actor_outbox_dslx).
-moduledoc "Independent per-actor batch storage for generated RAM schedulers.".
-export([emit/1, name/1]).

-doc "Emits outbox procs for an imported actor module. Pair with SharedService's PER_ACTOR_EGRESS parameter and route each returned credit to a separate scheduler producer.".
-spec emit(module()) -> binary().
emit(Module) ->
    Path = filename:join([code:priv_dir(erl_hls), "xls", "templates", "actor_outboxes.x"]),
    {ok, Template} = file:read_file(Path),
    Typed = binary:replace(Template, <<"actor::">>,
        <<(atom_to_binary(Module))/binary, "::">>, [global]),
    binary:replace(Typed, <<"ActorOutbox">>,
        <<(atom_to_binary(Module))/binary, "_ActorOutbox">>, [global]).

-doc "Returns the generated proc name; its COUNT parameter equals the scheduler's actor count.".
-spec name(module()) -> string().
name(Module) -> atom_to_list(Module) ++ "_ActorOutboxBank".
