%% Type and function imports also work for hls_gs, including nested types
%% declared in an include. Compiled through Top by the RTL regression runner.
-module(hls_companion_gs_fixture).
-hls_data(state).
-hls_tags([query, reply]).
-hls_replies([{query, [reply]}]).
-include("hls_companion_types.hrl").

-record(reply, {value = hls_type:zero() :: hls_companion_provider:scalar()}).
-record(state, {value = hls_type:zero() :: hls_companion_provider:scalar()}).

%% Starts the source-only companion fixture with zero scalar state.
-spec init([]) -> #state{}.
init([]) -> #state{}.

%% Exercises nested type imports and qualified companion arithmetic.
-spec handle_call(#query{}, #state{}) -> {reply, #reply{}, #state{}}.
handle_call(#query{values = Values}, State) ->
    [First, Second] = Values,
    Sum = hls_vec:dot(hls_fixed:signed(72, 32), Values, Values),
    Rounded = hls_fixed:round_ratio(Sum, 12),
    Clamped = hls_fixed:saturate(hls_fixed:signed(32, 16), Rounded),
    Value = hls_companion_provider:combine(First, Second, Clamped),
    {reply, #reply{value = Value}, State#state{value = Value}}.

%% Retains a returned scalar without adding a reply.
-spec handle_cast(#reply{}, #state{}) -> {noreply, #state{}}.
handle_cast(#reply{value = Value}, State) ->
    {noreply, State#state{value = Value}}.
