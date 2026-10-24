-module(xls_protocol_application).
-moduledoc "Binds an application identity and endpoint count to the existing ordered DSLX gateway.".
-export([emit/1, write/2]).

-doc "Writes a structural gateway proc for a freshly source-checked host binding. All framing, attachment, ordering and event serialization state remains in hls_partition_io::OrderedBoundary; the separately connected activation bridge supplies actual start completion.".
-spec write(map(),file:filename()) -> ok.
write(Binding, Directory) ->
    file:write_file(filename:join(Directory, "gateway.x"), emit(Binding), [exclusive]).

-doc "Returns the gateway DSLX bytes from a checked binding and the installed template. Framing and ordering remain in the shared gateway; no output files are created.".
-spec emit(map()) -> iodata().
emit(#{identity:=Identity,host:=Host,control:=Control,events:=Events}) ->
    Args=lists:join(", ",["u64:"++integer_to_list(Word)||<<Word:64/little>><=Identity]),
    {ok,Template}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/templates/protocol_application.x.in")),
    Source=lists:foldl(fun({Key,Value},Text)->binary:replace(Text,Key,Value,[global]) end,Template,
        [{<<"@@COUNT@@">>,integer_to_binary(map_size(Events))},{<<"@@IDENTITY@@">>,iolist_to_binary(Args)},
         {<<"@@HOST@@">>,integer_to_binary(Host)},{<<"@@CONTROL@@">>,integer_to_binary(Control)}]),
    Source.
