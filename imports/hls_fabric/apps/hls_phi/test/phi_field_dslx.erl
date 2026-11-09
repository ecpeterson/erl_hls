%%%% phi_field_dslx
%%%%
%%%% Staging-only arithmetic checks for the phi field companion and its BEAM implementation.

-module(phi_field_dslx).

-export([to_dslx/0]).

-define(S32_MIN, (-(1 bsl 31))).
-define(S32_MAX, ((1 bsl 31) - 1)).

-doc "Emits finite rounding and boundary witnesses comparing DSLX recurrences with BEAM results.".
-spec to_dslx() -> iolist().
to_dslx() ->
    [
        "// Generated staging test for phi_field.\n",
        "// This file is not a checked artifact.\n\n",
        "import phi_field;\n\n",
        "#[test]\n",
        "fn lowered_recurrences_match_beam_test() {\n",
        rounding_assertions(),
        boundary_assertions(),
        "}\n\n",
        "// The line split retains exact signed numerators across the owner boundary.\n",
        "#[test]\n",
        "fn lowered_line_stages_match_beam_test() {\n",
        line_assertions(),
        "}\n"
    ].

%% Emit finite rounding witnesses covering numerator residues from -48 through 48.
-spec rounding_assertions() -> iolist().
rounding_assertions() ->
    lists:append([
        [
            center_assertion(0, 0, 0, Numerator),
            bulk_assertion(0, 0, Numerator)
        ]
        || Numerator <- lists:seq(-48, 48)
    ]).

%% Emit a Cartesian sample of scalar and four-neighbor accumulator limits.
-spec boundary_assertions() -> iolist().
boundary_assertions() ->
    Fields = [?S32_MIN, -1, 0, 1, ?S32_MAX],
    NeighborSums = [4 * ?S32_MIN, -4, 0, 4, 4 * ?S32_MAX],
    lists:append([
        [
            center_assertion(0, Phi0, Phi1, NeighborSum),
            center_assertion(1, Phi0, Phi1, NeighborSum),
            bulk_assertion(Phi0, Phi1, NeighborSum)
        ]
        || Phi0 <- Fields,
           Phi1 <- Fields,
           NeighborSum <- NeighborSums
    ]).

%% Bound the line witness to signed half ties and representative two-neighbor extremes.
-spec line_assertions() -> iolist().
line_assertions() ->
    Extremes = [
        {?S32_MIN, ?S32_MIN, 2 * ?S32_MIN, 2 * ?S32_MIN},
        {?S32_MAX, ?S32_MAX, 2 * ?S32_MAX, 2 * ?S32_MAX},
        {?S32_MIN, ?S32_MAX, 2 * ?S32_MAX, 2 * ?S32_MIN},
        {?S32_MAX, ?S32_MIN, 2 * ?S32_MIN, 2 * ?S32_MAX}
    ],
    Cases = [{0, 0, N, -N} || N <- lists:seq(-9, 9)] ++ Extremes,
    [line_assertion(A, P, Q, S, T) || A <- [0, 1], {P, Q, S, T} <- Cases].

%% Check retained partials independently and then compare the lowered finish with BEAM.
-spec line_assertion(0 | 1, phi_field:scalar(), phi_field:scalar(),
    phi_field:accumulator(), phi_field:accumulator()) -> iolist().
line_assertion(Anyon, Phi0, Phi1, Sum0, Sum1) ->
    Numerators = [4 * Phi0 + 2 * Phi1 + Sum0, Phi0 + 5 * Phi1 + Sum1],
    [Center, Bulk] = Numerators,
    [Final0, Final1] = phi_field:relax_line(Anyon, [Phi0, Phi1], Sum0, Sum1),
    Partial = ["phi_field::line_numerators([", signed_literal(32, Phi0), ", ",
        signed_literal(32, Phi1), "], ", signed_literal(64, Sum0), ", ",
        signed_literal(64, Sum1), ")"],
    [
        "  assert_eq(", Partial, ", [sN[36]:", integer_to_list(Center),
        ", sN[36]:", integer_to_list(Bulk), "]);\n",
        "  assert_eq(phi_field::finish_line(", unsigned_literal(Anyon), ", ",
        Partial, "), [", signed_literal(32, Final0), ", ",
        signed_literal(32, Final1), "]);\n"
    ].

%% Render one center recurrence assertion against its BEAM-computed result.
-spec center_assertion(0 | 1, phi_field:scalar(), phi_field:scalar(),
    phi_field:accumulator()) -> iolist().
center_assertion(Anyon, Phi0, Phi1, NeighborSum) ->
    Expected = phi_field:relax_center(Anyon, Phi0, Phi1, NeighborSum),
    [
        "  assert_eq(phi_field::relax_center(", unsigned_literal(Anyon), ", ",
        signed_literal(32, Phi0), ", ", signed_literal(32, Phi1), ", ",
        signed_literal(64, NeighborSum), "), ",
        signed_literal(32, Expected), ");\n"
    ].

%% Render one terminal bulk recurrence assertion against its BEAM-computed result.
-spec bulk_assertion(phi_field:scalar(), phi_field:scalar(),
    phi_field:accumulator()) -> iolist().
bulk_assertion(Phi0, Phi1, NeighborSum) ->
    Expected = phi_field:relax_bulk(Phi0, Phi1, NeighborSum),
    [
        "  assert_eq(phi_field::relax_bulk(", signed_literal(32, Phi0), ", ",
        signed_literal(32, Phi1), ", ", signed_literal(64, NeighborSum),
        "), ", signed_literal(32, Expected), ");\n"
    ].

%% Render an unsigned source term as a DSLX u32 literal.
-spec unsigned_literal(hls_nums:u32()) -> iolist().
unsigned_literal(Value) -> ["u32:", integer_to_list(Value)].

%% Render a signed DSLX literal with the explicitly selected bit width.
-spec signed_literal(pos_integer(), integer()) -> iolist().
signed_literal(Width, Value) ->
    ["s", integer_to_list(Width), ":", integer_to_list(Value)].
