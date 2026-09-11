%%%% phi_field_dslx
%%%%
%%%% Staging-only arithmetic checks for the phi field companion and its BEAM implementation.

-module(phi_field_dslx).

-export([to_dslx/0]).

-define(S32_MIN, (-(1 bsl 31))).
-define(S32_MAX, ((1 bsl 31) - 1)).

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
        "}\n"
    ].

rounding_assertions() ->
    lists:append([
        [
            center_assertion(0, 0, 0, Numerator),
            bulk_assertion(0, 0, Numerator)
        ]
        || Numerator <- lists:seq(-48, 48)
    ]).

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

center_assertion(Anyon, Phi0, Phi1, NeighborSum) ->
    Expected = phi_field:relax_center(Anyon, Phi0, Phi1, NeighborSum),
    [
        "  assert_eq(phi_field::relax_center(", unsigned_literal(Anyon), ", ",
        signed_literal(32, Phi0), ", ", signed_literal(32, Phi1), ", ",
        signed_literal(64, NeighborSum), "), ",
        signed_literal(32, Expected), ");\n"
    ].

bulk_assertion(Phi0, Phi1, NeighborSum) ->
    Expected = phi_field:relax_bulk(Phi0, Phi1, NeighborSum),
    [
        "  assert_eq(phi_field::relax_bulk(", signed_literal(32, Phi0), ", ",
        signed_literal(32, Phi1), ", ", signed_literal(64, NeighborSum),
        "), ", signed_literal(32, Expected), ");\n"
    ].

unsigned_literal(Value) -> ["u32:", integer_to_list(Value)].

signed_literal(Width, Value) ->
    ["s", integer_to_list(Width), ":", integer_to_list(Value)].
