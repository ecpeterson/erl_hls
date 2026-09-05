%%%% phi_field_dslx
%%%%
%%%% Staging-only arithmetic checks for the custom phi field lowering.

-module(phi_field_dslx).

-export([to_dslx/0]).

-include("../src/backend/xls/xls_parse.hrl").

-define(S32_MIN, (-(1 bsl 31))).
-define(S32_MAX, ((1 bsl 31) - 1)).

-spec to_dslx() -> iolist().
to_dslx() ->
    [
        "// Generated staging test for phi_field.\n",
        "// This file is not a checked artifact.\n\n",
        lowered_function(
            "relax_center",
            [
                {"anyon", "u32"},
                {"phi0", "s32"},
                {"phi1", "s32"},
                {"neighbor_sum", "s64"}
            ],
            relax_center
        ),
        lowered_function(
            "relax_bulk",
            [
                {"phi0", "s32"},
                {"phi1", "s32"},
                {"neighbor_sum", "s64"}
            ],
            relax_bulk
        ),
        reference_and_properties(),
        "#[test]\n",
        "fn lowered_recurrences_match_beam_test() {\n",
        rounding_assertions(),
        boundary_assertions(),
        "}\n"
    ].

reference_and_properties() ->
    """
    fn reference_round(numerator: s64, denominator: s64, half: s64) -> s64 {
      if numerator < s64:0 {
        (numerator - half) / denominator
      } else {
        (numerator + half) / denominator
      }
    }

    fn reference_saturate(value: s64) -> s32 {
      if value > s64:2147483647 {
        s32:2147483647
      } else if value < s64:-2147483648 {
        s32:-2147483648
      } else {
        value as s32
      }
    }

    fn neighbor_sum(a: s32, b: s32, c: s32, d: s32) -> s64 {
      (a as s64) + (b as s64) + (c as s64) + (d as s64)
    }

    #[quickcheck]
    fn center_matches_wide_reference(
        anyon: u1,
        phi0: s32,
        phi1: s32,
        north: s32,
        east: s32,
        west: s32,
        south: s32
    ) -> bool {
      let sum = neighbor_sum(north, east, west, south);
      let numerator =
        (phi0 as s64) * s64:6 + (phi1 as s64) * s64:2 + sum;
      let expected = reference_saturate(
        ((anyon as s64) << u32:16) +
          reference_round(numerator, s64:12, s64:6));
      relax_center(anyon as u32, phi0, phi1, sum) == expected
    }

    #[quickcheck]
    fn bulk_matches_wide_reference(
        phi0: s32,
        phi1: s32,
        north: s32,
        east: s32,
        west: s32,
        south: s32
    ) -> bool {
      let sum = neighbor_sum(north, east, west, south);
      let numerator =
        (phi0 as s64) + (phi1 as s64) * s64:7 + sum;
      let expected = reference_saturate(
        reference_round(numerator, s64:12, s64:6));
      relax_bulk(phi0, phi1, sum) == expected
    }

    """.

lowered_function(Name, Arguments, Function) ->
    References = [Reference || {Reference, _Type} <- Arguments],
    State = phi_field:transpile(
        Function,
        References,
        #clause_state{}
    ),
    [
        "fn ", Name, "(",
        join_with(", ", [
            [Reference, ": ", Type] || {Reference, Type} <- Arguments
        ]),
        ") -> s32 {\n",
        [["  ", Statement] || Statement <- lists:reverse(
            State#clause_state.statements
        )],
        "  ", State#clause_state.reference, "\n",
        "}\n\n"
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
        "  assert_eq(relax_center(", unsigned_literal(Anyon), ", ",
        signed_literal(32, Phi0), ", ", signed_literal(32, Phi1), ", ",
        signed_literal(64, NeighborSum), "), ",
        signed_literal(32, Expected), ");\n"
    ].

bulk_assertion(Phi0, Phi1, NeighborSum) ->
    Expected = phi_field:relax_bulk(Phi0, Phi1, NeighborSum),
    [
        "  assert_eq(relax_bulk(", signed_literal(32, Phi0), ", ",
        signed_literal(32, Phi1), ", ", signed_literal(64, NeighborSum),
        "), ", signed_literal(32, Expected), ");\n"
    ].

unsigned_literal(Value) -> ["u32:", integer_to_list(Value)].

signed_literal(Width, Value) ->
    ["s", integer_to_list(Width), ":", integer_to_list(Value)].

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
