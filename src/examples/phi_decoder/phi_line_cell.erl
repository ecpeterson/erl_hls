-module(phi_line_cell).
-moduledoc """
A two-neighbor phi cell for the periodic repetition-code example.

Only east/west halo, comparison and movement messages exist. Each barrier has
two participants; the mailbox retains one early barrier plus its release.
The two stored field layers use the normalized line recurrence in phi_field.
Configuration, measurements, correction/status ordering and twelve diffusion
rounds follow phi_halo_cell. North/south are not output channels.
""".

-define(PHI_REPETITION, true).
-include("phi_halo_cell_impl.hrl").
