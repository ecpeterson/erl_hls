-module(phi_halo_cell_runtime).
-moduledoc """
CPU scheduler for the lowerable `phi_halo_cell` arithmetic kernel.

The outer state is either `gathering` or `ready`.  Halo values, the direction
ready mask, and the epoch counter live in the inner kernel data, so updating
them does not by itself make postponed events eligible.  The final
current-epoch halo explicitly changes the outer state to `ready`; a current
diffuse call changes it back to `gathering`.  Those two transitions, and only
those transitions, cause `xls_statem` to retry postponed events.

The scheduler admits the current epoch and one look-ahead epoch.  A look-ahead
event is postponed; an older or farther-future event is a protocol error rather
than an event which can occupy bounded capacity forever.
""".

-behaviour(xls_statem).

-export([callback_mode/0, init/1, handle_event/4]).

-define(U32_MASK, 16#ffffffff).

callback_mode() ->
    handle_event_function.

init(Arg) ->
    {ok, gathering, phi_halo_cell:init(Arg)}.

handle_event(cast, Event, StateName, Data)
        when StateName =:= gathering; StateName =:= ready ->
    halo = phi_halo_cell:event_kind(Event),
    case epoch_relation(Event, Data) of
        next ->
            {keep_state_and_data, [postpone]};
        current ->
            {noreply, NextData} = phi_halo_cell:handle_cast(Event, Data),
            case phi_halo_cell:phase_ready(NextData) of
                true -> {next_state, ready, NextData};
                false -> {keep_state, NextData}
            end
    end;
handle_event({call, _From}, Event, gathering, Data) ->
    diffuse = phi_halo_cell:event_kind(Event),
    case epoch_relation(Event, Data) of
        next -> {keep_state_and_data, [postpone]};
        current -> {keep_state_and_data, [postpone]}
    end;
handle_event({call, From}, Event, ready, Data) ->
    diffuse = phi_halo_cell:event_kind(Event),
    case epoch_relation(Event, Data) of
        next ->
            {keep_state_and_data, [postpone]};
        current ->
            {reply, Reply, NextData} =
                phi_halo_cell:handle_call(Event, Data),
            {next_state,
                gathering,
                NextData,
                [{reply, From, Reply}]}
    end.

epoch_relation(Event, Data) ->
    EventEpoch = phi_halo_cell:event_epoch(Event),
    CurrentEpoch = phi_halo_cell:state_epoch(Data),
    case EventEpoch of
        CurrentEpoch ->
            current;
        _ ->
            NextEpoch = (CurrentEpoch + 1) band ?U32_MASK,
            case EventEpoch of
                NextEpoch -> next;
                _ -> error({invalid_phi_epoch, CurrentEpoch, EventEpoch})
            end
    end.
