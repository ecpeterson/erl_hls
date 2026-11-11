-module(xls_provider_enum).
-moduledoc "Compiler companion for hls_enum. Finite source atoms lower to explicitly typed bits at their declared type boundary; raw unused codes remain representable for wildcard rejection. Host atom packing belongs to hls_enum.".
-behaviour(xls_type).

%% Compiler provider type rendering; there are no runtime enum operations.
-export([print_type/2]).

-doc "Renders the compact encoded value without a target-language enum cast.".
-spec print_type(enum, [hls_type:arg()]) -> iodata().
print_type(enum, [Members]) ->
    case lists:member(true, Members) orelse lists:member(false, Members) of
        true -> error({unsupported_xls_boolean_enum, Members});
        false -> ["uN[", integer_to_list(hls_enum:width(enum, [Members])), "]"]
    end.
