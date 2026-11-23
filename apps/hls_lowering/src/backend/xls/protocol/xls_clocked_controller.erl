-module(xls_clocked_controller).
-moduledoc "Compiles immediate Erlang control kernels for sampled domain/endpoint clocks. Uses the common actor transition and reply checks, without a mailbox, host caller retention or a second server compiler.".
-export([artifact/2]).

-doc "Emit one immediate server transition per caller-owned clock. Rejects state machines, retained calls, continuations and non-reply publications. The enclosing composer owns cold reset and never submits application traffic here.".
-spec artifact(file:filename(), hls_frame_layout:words()) -> xls_emitted:artifact().
artifact(Source, Words) ->
    Spec = xls_parse:actor_artifact(Source, [], hls_frame_layout:new(Words)),
    case Spec of
        #{
            source_kind := server,
            retained_calls := #{mode := immediate},
            continuations := [],
            output_names := [reply],
            data_name := Data
        } ->
            Actor = xls_activation_codegen:artifact(Spec),
            {ok, Body} = file:read_file(
                filename:join(
                    code:priv_dir(hls_lowering),
                    "xls/templates/clocked_controller.x.in"
                )
            ),
            xls_emitted:with_bytes(Actor, [
                xls_emitted:bytes(Actor),
                "\n// Typed source data, independent of the execution-state packing.\n",
                "pub type ClockData = ",
                xls_names:record_type(Data),
                ";\n",
                Body
            ]);
        _ ->
            hls_diagnostic:raise(
                domain,
                unsupported_clocked_controller,
                <<"Clocked controllers require an immediate server with only its reply output and no continuations.">>,
                #{source => Source}
            )
    end.
