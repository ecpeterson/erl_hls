-module(xls_provider_record).
-moduledoc "Compiler companion for hls_record. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([print_type/2, dslx_codec/2]).

-doc "Names the ordinary DSLX struct used for this record value.".
-spec print_type(atom(), hls_record:fields()) -> string().
print_type(Name, _Fields) -> xls_names:record_type(Name).

-doc "Uses the record's generated field-wise codecs, preserving nested padding.".
-spec dslx_codec(atom(), hls_record:fields()) -> xls_type:codec().
dslx_codec(Name, _Fields) ->
    Codec = xls_names:record_codec(Name),
    {fun(Bits) -> [Codec, "_from_bits(", Bits, ")"] end, fun(Value) ->
        ["bits_from_", Codec, "(", Value, ")"]
    end}.
