%% Type and function imports also work for hls_gs, including nested types
%% declared in an include. Compiled through Top by the RTL regression runner.
-module(hls_companion_gs_fixture).
-hls_data(state).
-hls_tags([query, reply]).
-include("hls_companion_types.hrl").

-record(reply, {value = hls_type:zero() :: phi_field:scalar()}).
-record(state, {value = hls_type:zero() :: phi_field:scalar()}).

init([]) -> #state{}.

handle_call(#query{values = Values}, State) ->
    Phi0 = hls_lists:nth(1, Values),
    Phi1 = hls_lists:nth(2, Values),
    Sum = hls_vec:dot(hls_fixed:signed(72, 32), Values, Values),
    Rounded = hls_fixed:round_ratio(Sum, 12),
    Clamped = hls_fixed:saturate(hls_fixed:signed(32, 16), Rounded),
    Value = phi_field:relax_bulk(Phi0, Phi1, hls_type:as(hls_nums:s64(), Clamped)),
    {reply, #reply{value = Value}, State#state{value = Value}}.

handle_cast(#reply{value = Value}, State) ->
    {noreply, State#state{value = Value}}.
