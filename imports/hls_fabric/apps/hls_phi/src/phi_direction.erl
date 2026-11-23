-module(phi_direction).
-moduledoc """
Pure tie selection shared by the line and grid Phi actors.

The comparison reduction supplies a mask of equally maximal neighbors. The
cell wrappers select the geometry policy; both policies use the low 31 bits
of the existing random word, leaving its high coin bit independent. Ordinary
source-helper lowering compiles these functions without a DSLX companion or
provider callback and introduces no scheduling boundary.
""".

%% Direction bits share the message schema's authority; this helper emits no messages.
-include("../include/phi_protocol.hrl").

%% Geometry policies used by Phi comparison completion.
-export([select_line/2, select_grid/2]).

-doc "Selects east or west from masks 2, 4 or 6, splitting a tie at random bit 30. Returns zero for every other mask and ignores the random word's high coin bit.".
-spec select_line(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
select_line(Mask, Random) ->
    case Mask of
        ?PHI_EAST_MASK ->
            ?PHI_EAST_MASK;
        ?PHI_WEST_MASK ->
            ?PHI_WEST_MASK;
        _ when Mask =:= (?PHI_EAST_MASK bor ?PHI_WEST_MASK) ->
            case Random band 16#40000000 of
                0 -> ?PHI_EAST_MASK;
                _ -> ?PHI_WEST_MASK
            end;
        _ ->
            0
    end.

-doc "Ranks the low-31-bit draw among set north/east/west/south bits in that order. Ignores mask bits above bit 3 and returns zero for an empty low mask; three-way bucket sizes differ by one draw.".
-spec select_grid(hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
select_grid(Mask, Random) ->
    North = Mask band 1,
    East = (Mask bsr 1) band 1,
    West = (Mask bsr 2) band 1,
    South = (Mask bsr 3) band 1,
    Count = North + East + West + South,
    Draw = hls_type:as(hls_nums:u64(), Random band 16#7fffffff),
    Rank = hls_type:as(
        hls_nums:u32(),
        (Draw * hls_type:as(hls_nums:u64(), Count)) bsr 31
    ),
    if
        Count =:= 0 -> 0;
        Rank < North -> ?PHI_NORTH_MASK;
        Rank < North + East -> ?PHI_EAST_MASK;
        Rank < North + East + West -> ?PHI_WEST_MASK;
        true -> ?PHI_SOUTH_MASK
    end.
