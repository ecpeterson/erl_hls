%%%% phi_halo_cell.erl
%%%%
%%%% A CPU-first compile probe for one cell of a two-layer, three-dimensional
%%%% halo/Jacobi update.  The four in-plane neighbors each supply both layers;
%%%% the opposite layer in the same cell supplies the two z-direction terms.

-module(phi_halo_cell).
-moduledoc """
A lowerable reference kernel for one two-layer cell of the three-dimensional
field update in the phi-decoder (arXiv:1406.2338, equation 4).

The two layers form the smallest periodic z dimension: each layer sees the
other layer twice.  Four in-plane halo records carry both layers.  `diffuse/3`
applies the Jacobi recurrence with `eta = 3/8`; following equation 4, `eta`
names the neighbor-mixing weight, so the retained self weight is `1-eta=5/8`.
Charge is injected only into layer zero, where the two-dimensional syndrome
plane is embedded.

Field values are unsigned Q16.16 in the intended deployment.  Arithmetic is
deliberately modular `u32` in both the CPU reference and generated DSLX.  A
later numeric policy may replace wraparound with a wider accumulator or
saturation.

These callbacks are the arithmetic kernel, not yet a network-facing actor.
The future fabric scheduler must stage out-of-order messages and deliver only
one halo per direction for the kernel's current epoch.  Calling the exported
CPU harness with a future or duplicate halo violates that runtime contract.
""".

-export([
    offer_north/3,
    offer_east/3,
    offer_west/3,
    offer_south/3,
    diffuse/3
]).
-export([start_link/0, stop/1]).
-export([init/1, handle_call/2, handle_cast/2]).

-behavior(xls_gs).
-xls_tags([halo_n, halo_e, halo_w, halo_s, diffuse, field]).
-compile({parse_transform, xls_pack}).

-define(LAYER_COUNT, 2).
-define(U32_MASK, 16#ffffffff).

-define(NORTH_READY, 1).
-define(EAST_READY, 2).
-define(WEST_READY, 4).
-define(SOUTH_READY, 8).
-define(ALL_READY, 15).

%% Potentials and charge use unsigned Q16.16 values in the intended deployment.
%% The Jacobi coefficients are represented by integer numerators over sixteen,
%% so the right shift preserves the Q16.16 scale.  Small raw integers are also
%% useful for exact, hand-checkable CPU tests.

-record(halo_n, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(halo_e, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(halo_w, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(halo_s, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(diffuse, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    charge = xls_type:zero() :: xls_nums:u32()
}).

-record(field, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    values = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT)
}).

-record(state, {
    epoch = xls_type:zero() :: xls_nums:u32(),
    phi = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    north = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    east = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    west = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    south = xls_type:zero() ::
        xls_lists:list(xls_nums:u32(), ?LAYER_COUNT),
    ready = xls_type:zero() :: xls_nums:u8()
}).

%%%
%%% Client interface
%%%

-spec offer_north(pid(), xls_nums:u32(), [xls_nums:u32()]) -> ok.
offer_north(PID, Epoch, Values) ->
    gen_server:cast(PID, #halo_n{epoch = Epoch, values = Values}).

-spec offer_east(pid(), xls_nums:u32(), [xls_nums:u32()]) -> ok.
offer_east(PID, Epoch, Values) ->
    gen_server:cast(PID, #halo_e{epoch = Epoch, values = Values}).

-spec offer_west(pid(), xls_nums:u32(), [xls_nums:u32()]) -> ok.
offer_west(PID, Epoch, Values) ->
    gen_server:cast(PID, #halo_w{epoch = Epoch, values = Values}).

-spec offer_south(pid(), xls_nums:u32(), [xls_nums:u32()]) -> ok.
offer_south(PID, Epoch, Values) ->
    gen_server:cast(PID, #halo_s{epoch = Epoch, values = Values}).

-spec diffuse(pid(), xls_nums:u32(), xls_nums:u32()) ->
    {NextEpoch :: xls_nums:u32(), Values :: [xls_nums:u32()]}.
diffuse(PID, Epoch, Charge) ->
    #field{epoch = NextEpoch, values = Values} =
        gen_server:call(PID, #diffuse{epoch = Epoch, charge = Charge}),
    {NextEpoch, Values}.

%%%
%%% Server management
%%%

-spec start_link() -> {ok, pid()}.
start_link() ->
    xls_gs:start_link(?MODULE, []).

-spec stop(pid()) -> ok.
stop(PID) ->
    xls_gs:stop(PID).

%%%
%%% xls_gs callbacks
%%%

-spec init(any()) -> #state{}.
init([]) ->
    #state{}.

handle_cast(
    #halo_n{epoch = Epoch, values = Values},
    State
) ->
    Epoch = State#state.epoch,
    Ready = State#state.ready,
    true = (Ready band ?NORTH_READY) < ?NORTH_READY,
    {noreply, State#state{
        north = Values,
        ready = Ready bor ?NORTH_READY
    }};
handle_cast(
    #halo_e{epoch = Epoch, values = Values},
    State
) ->
    Epoch = State#state.epoch,
    Ready = State#state.ready,
    true = (Ready band ?EAST_READY) < ?EAST_READY,
    {noreply, State#state{
        east = Values,
        ready = Ready bor ?EAST_READY
    }};
handle_cast(
    #halo_w{epoch = Epoch, values = Values},
    State
) ->
    Epoch = State#state.epoch,
    Ready = State#state.ready,
    true = (Ready band ?WEST_READY) < ?WEST_READY,
    {noreply, State#state{
        west = Values,
        ready = Ready bor ?WEST_READY
    }};
handle_cast(
    #halo_s{epoch = Epoch, values = Values},
    State
) ->
    Epoch = State#state.epoch,
    Ready = State#state.ready,
    true = (Ready band ?SOUTH_READY) < ?SOUTH_READY,
    {noreply, State#state{
        south = Values,
        ready = Ready bor ?SOUTH_READY
    }}.

handle_call(
    #diffuse{epoch = Epoch, charge = Charge},
    State
) ->
    Epoch = State#state.epoch,
    Ready = State#state.ready,
    true = ?ALL_READY < Ready + 1,

    P0 = xls_lists:nth(1, State#state.phi),
    P1 = xls_lists:nth(2, State#state.phi),
    N0 = xls_lists:nth(1, State#state.north),
    N1 = xls_lists:nth(2, State#state.north),
    E0 = xls_lists:nth(1, State#state.east),
    E1 = xls_lists:nth(2, State#state.east),
    W0 = xls_lists:nth(1, State#state.west),
    W1 = xls_lists:nth(2, State#state.west),
    S0 = xls_lists:nth(1, State#state.south),
    S1 = xls_lists:nth(2, State#state.south),

    %% Jacobi diffusion with eta = 3/8.  Layer 0 carries the local charge;
    %% layer 1 is the charge-free neighboring z layer.
    Numerator0 = ((xls_nums:u32_shl(P0, 3) +
        xls_nums:u32_shl(P0, 1)) + xls_nums:u32_shl(P1, 1) +
        N0 + E0 + W0 + S0) band ?U32_MASK,
    Numerator1 = ((xls_nums:u32_shl(P1, 3) +
        xls_nums:u32_shl(P1, 1)) + xls_nums:u32_shl(P0, 1) +
        N1 + E1 + W1 + S1) band ?U32_MASK,
    New0 = (Charge + xls_nums:u32_shr(Numerator0, 4)) band ?U32_MASK,
    New1 = xls_nums:u32_shr(Numerator1, 4),
    Phi0 = xls_lists:set(1, State#state.phi, New0),
    NewPhi = xls_lists:set(2, Phi0, New1),
    NextEpoch = (Epoch + 1) band ?U32_MASK,

    {reply,
        #field{epoch = NextEpoch, values = NewPhi},
        State#state{epoch = NextEpoch, phi = NewPhi, ready = 0}}.
