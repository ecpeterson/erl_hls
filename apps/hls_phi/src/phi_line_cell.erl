-module(phi_line_cell).
-moduledoc """
A two-neighbor phi cell for the periodic repetition-code example.

Only east/west halo, comparison and movement messages exist. Each barrier has
two participants; the mailbox retains one early barrier plus its release.
The two stored field layers use the normalized line recurrence in phi_field.
Configuration, measurements, correction/status ordering and twelve diffusion
rounds follow phi_halo_cell. North/south are not output channels.

Diffusion completion retains weighted numerators; the next state entry rounds,
injects the anyon and saturates before publishing. The protocol owner registers
that callback boundary without adding an activation. Pending arithmetic belongs
to the private transition and is cleared by successful entry.

Shares phi_halo_cell_impl.hrl with the grid wrapper; phi_repetition_topology selects this geometry for its decoder family.
""".

-define(PHI_REPETITION, true).
%% Geometry-owned interface and storage; protocol records precede actor state.
-include("../include/phi_protocol.hrl").
-hls_outputs([east, west, syndrome, correction, status]).

-hls_mailbox_capacity(3).

-include("../include/phi_line_state.hrl").

%% Required connections for the two-neighbor protocol.
-type neighbors() :: #{
    east := pid(),
    west := pid(),
    syndrome := pid(),
    correction := pid(),
    status := pid()
}.

-include("../include/phi_halo_cell_impl.hrl").

%% The geometry wrapper selects an ordinary source helper; neither call adds a phase.
-spec choose_direction(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
choose_direction(Mask, Random) -> phi_direction:select_line(Mask, Random).

%% Retain the arithmetic prefix in the ordinary completion-to-entry transition.
-spec prepare_diffusion(#cell{}, hls_nums:s64(), hls_nums:s64()) -> #cell{}.
prepare_diffusion(Cell, Sum0, Sum1) ->
    Cell#cell{
        numerators = phi_field:line_numerators(Cell#cell.phi, Sum0, Sum1),
        numerical_pending = 1
    }.

%% Entry may be retried under backpressure; only its returned data clears the work.
-spec finish_diffusion(#cell{}) -> #cell{}.
finish_diffusion(Cell = #cell{numerical_pending = 1}) ->
    Cell#cell{
        phi = phi_field:finish_line(Cell#cell.anyon, Cell#cell.numerators),
        numerators = hls_lists:new(hls_nums:sN(36), 2),
        numerical_pending = 0
    };
finish_diffusion(Cell) ->
    Cell.
