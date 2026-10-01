-module(phenom_line_data_cell).
-moduledoc """
A repetition-code data qubit with two neighboring syndrome checks.

Two distinct east/west queries release one reproducible Bernoulli Z error.
Replies report that same error to both checks. Cutoff, Pauli updates and final
measurement queries follow phenom_data_cell; no orthogonal traffic exists.
""".

-define(PHI_REPETITION, true).
-include("phenom_data_cell_impl.hrl").
