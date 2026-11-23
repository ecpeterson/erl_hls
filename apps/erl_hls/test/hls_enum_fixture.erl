-module(hls_enum_fixture).
-moduledoc false.
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_tags([request, response, cast_request]).
-hls_replies([{request, [response]}]).
-export([init/1, handle_call/2, handle_cast/2]).
%% Overlapping atoms intentionally occupy different positions in these domains.
-type mode() :: idle | busy | done.
%% The busy atom has code two here and code one in mode().
-type fault() :: none | actor | busy.
-record(cell, {phase = idle :: mode(), fault = none :: fault()}).
-record(request, {phase = idle :: mode()}).
-record(cast_request, {phase = idle :: mode()}).
-record(response, {phase = idle :: mode(), fault = none :: fault()}).

-doc "Initializes the finite atom record fixture.".
-spec init([]) -> #cell{}.
init([]) -> #cell{}.

-doc "Exercises helper clauses, guards, case patterns and contextual enum construction.".
-spec handle_call(#request{}, #cell{}) -> {reply, #response{}, #cell{}}.
handle_call(#request{phase = Mode}, Cell) ->
    Next = choose(Mode),
    Fault = case Next of busy -> busy; _ -> none end,
    {reply, #response{phase = Next, fault = Fault}, Cell#cell{phase = Next, fault = Fault}}.

-doc "Exercises field update with a typed helper result.".
-spec handle_cast(#cast_request{}, #cell{}) -> {noreply, #cell{}}.
handle_cast(#cast_request{phase = Mode}, Cell) -> {noreply, Cell#cell{phase = choose(Mode)}}.

%% The same ordinary Erlang helper reaches head, guard and case lowering.
-spec choose(mode()) -> mode().
choose(idle) -> busy;
choose(X) when X =:= busy -> done;
choose(X) -> case X of done -> idle; Other -> Other end.
