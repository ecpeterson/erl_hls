-module(hls_host_codec_plan).
-moduledoc "Binds checked actor-interface records and output domains into runtime-owned host codec catalogs. Partition, application and scheduled-node planners call this once while source metadata is available; retained packing and provider checks remain in hls_host_codec.".

%% Interface-to-wire descriptor derivation.
-export([schemas/1, outputs/1]).

-doc "Captures every checked record for compiler-owned packing with current compatible providers. No actor module is required to use the returned codecs.".
-spec schemas(hls_actor_interface:summary()) -> hls_host_codec:catalog().
schemas(#{schemas := Schemas}) ->
    maps:from_list([
        begin
            Codec = hls_record_codec:bind(Name, [{N, T} || #{name := N, type := T} <- Fields]),
            {Name, #{
                name => Name,
                selector => Selector,
                width => hls_record_codec:width(Codec),
                codec => Codec
            }}
        end
     || #{name := Name, selector := Selector, fields := Fields} <- Schemas
    ]).

-doc "Retains the checked record-name union for each actor output port, independent of later actor reloads.".
-spec outputs(hls_actor_interface:summary()) -> #{atom() => [atom()]}.
outputs(Interface = #{entry_effects := Entry}) ->
    Ports = lists:usort([Port || #{port := Port} <- Entry ++ maps:get(reply_effects, Interface, [])]),
    maps:from_list([{Port, hls_actor_interface:output_schemas(Interface, Port)} || Port <- Ports]).
