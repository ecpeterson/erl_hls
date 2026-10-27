-module(hls_host_codec).
-moduledoc "Retained host record schemas and output domains from one checked actor interface.".
-export([schemas/1, outputs/1, check/1]).
-export_type([schema/0, catalog/0]).

-doc "An actor-local selector and its retained record layout, interpreted by current codec providers.".
-type schema() :: #{name := atom(), selector := byte(), width := non_neg_integer(),
    codec := hls_record_codec:codec()}.
-doc "Record names mapped to the codecs captured during planning.".
-type catalog() :: #{atom() => schema()}.

-doc "Captures every checked record for compiler-owned packing with current compatible providers. No actor module is required to use the returned codecs.".
-spec schemas(hls_actor_interface:summary()) -> catalog().
schemas(#{schemas := Schemas}) ->
    maps:from_list([begin
        Codec = hls_record_codec:bind(Name, [{N, T} || #{name := N, type := T} <- Fields]),
        {Name, #{name => Name, selector => Selector,
            width => hls_record_codec:width(Codec), codec => Codec}}
    end || #{name := Name, selector := Selector, fields := Fields} <- Schemas]).

-doc "Retains the checked record-name union for each actor output port, independent of later actor reloads.".
-spec outputs(hls_actor_interface:summary()) -> #{atom() => [atom()]}.
outputs(Interface = #{entry_effects := Entry}) ->
    Ports = lists:usort([Port || #{port := Port} <- Entry ++ maps:get(reply_effects, Interface, [])]),
    maps:from_list([{Port, hls_actor_interface:output_schemas(Interface, Port)} || Port <- Ports]).

-doc "Checks current codec availability and retained widths before opening a host session. This does not verify semantic compatibility.".
-spec check(catalog()) -> ok.
check(Schemas) ->
    maps:foreach(fun(_, #{codec := Codec}) -> hls_record_codec:check(Codec) end, Schemas).
