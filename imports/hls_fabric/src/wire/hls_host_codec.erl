-module(hls_host_codec).
-moduledoc "Retained host record catalogs and runtime provider checks. hls_host_codec_plan binds these descriptors from checked source interfaces; runtime codecs consume them without reacquiring source or calling actor packers.".
%% Runtime provider availability.
-export([check/1]).
-export_type([schema/0, catalog/0]).

-doc "An actor-local selector and its retained record layout, interpreted by current codec providers.".
-type schema() :: #{
    name := atom(),
    selector := byte(),
    width := non_neg_integer(),
    codec := hls_record_codec:codec()
}.
-doc "Record names mapped to the codecs captured during planning.".
-type catalog() :: #{atom() => schema()}.

-doc "Checks current codec availability and retained widths before opening a host session. This does not verify semantic compatibility.".
-spec check(catalog()) -> ok.
check(Schemas) ->
    maps:foreach(fun(_, #{codec := Codec}) -> hls_record_codec:check(Codec) end, Schemas).
