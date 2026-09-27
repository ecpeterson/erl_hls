-module(phenom_line_syndrome_cell).
-moduledoc """
A weight-two X check for the phase-flip repetition-code example.

Two distinct east/west data replies contribute to each detection event,
together with the current and preceding measurement-error draws. Requests,
cutoff and the one-result lookahead follow phenom_syndrome_cell. There are no
north/south channels or implicit self-responses.
""".

-define(PHI_REPETITION, true).
-include("phenom_syndrome_cell_impl.hrl").
