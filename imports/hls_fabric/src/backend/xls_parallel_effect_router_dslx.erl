-module(xls_parallel_effect_router_dslx).
-moduledoc "Bounded publication windows with topology-checked recipient conflicts.".
-export([emit/6]).

-doc "Emits a router that preserves per-recipient effect order and the ordinary bounded reservation protocol. Masks use actual destination lanes, including multicast and aliased ports.".
-spec emit(map(), pos_integer(), pos_integer(), [iodata()], iodata(), iodata()) -> binary().
emit(#{index := Index, module_name := Module}, Width, Lanes, Arguments, Targets, Sends) ->
    Path = filename:join([code:priv_dir(hls_fabric), "xls", "templates", "parallel_effect_router.x.in"]),
    {ok, Template} = file:read_file(Path),
    Members = [["scheduled_in: chan<", Module, "::ScheduledEffects> in"],
        ["credit_out: chan<", Module, "::ScheduledRequest> out"]] ++ Arguments ++
        ["window_request_out: chan<u1> out", "window_grant_in: chan<u1> in",
         "window_release_out: chan<u1> out"],
    Names = [hd(string:split(binary_to_list(iolist_to_binary(A)), ":")) || A <- Members],
    Body = xls_template:render(Template, [
        {<<"@@MEMBERS@@">>, [["  ", M, ";\n"] || M <- Members]},
        {<<"@@ARGUMENTS@@">>, lists:join(", ", Members)},
        {<<"@@NAMES@@">>, lists:join(", ", Names)}, {<<"@@SENDS@@">>, Sends}]),
    Prefix = "SchedulerRouter" ++ integer_to_list(Index),
    Replacements = [{"ACTOR::", Module ++ "::"}, {"RouterHead", Prefix ++ "Head"},
        {"RouterState", Prefix ++ "State"}, {"proc Router ", "proc " ++ Prefix ++ " "},
        {"router_head", Prefix ++ "_head"}, {"router_targets", Prefix ++ "_targets"},
        {"router_frame", Prefix ++ "_frame"}, {"WIDTH", "u32:" ++ integer_to_list(Width)},
        {"LANES", "u32:" ++ integer_to_list(Lanes)}],
    lists:foldl(fun({Before, After}, Text) ->
        binary:replace(Text, list_to_binary(Before), list_to_binary(After), [global])
    end, iolist_to_binary([Targets, Body]), Replacements).
