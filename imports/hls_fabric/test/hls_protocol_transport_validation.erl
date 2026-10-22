-module(hls_protocol_transport_validation).
-moduledoc "Prepares independent ordinary-decoder references for the production transport output.".
-export([prepare/1]).
-doc "Reads a fresh trusted local transport build, writes ordinary DSLX effect decoders and a finite-witness catalogue. The RTL scoreboard uses these ordinary decoders, not the publisher's bit projection, to check frames. This is test preparation, not application admission.".
-spec prepare(file:filename()) -> ok.
prepare(Directory) ->
    {ok, Bytes} = file:read_file(filename:join(Directory, "transport.etf")),
    #{bundle := #{modules := Modules}, sources := #{sources := Sources},
      capture := #{channels := Channels}, fabric := #{links := Links, boundaries := Boundaries}} = binary_to_term(Bytes),
    [{Module, #{spec := Spec}}] = maps:to_list(Modules),
    ok = file:write_file(filename:join(Directory, "reference.x"), xls_shared_codegen:execution(Spec), [exclusive]),
    Pairs = [begin
        SlotRows = [begin
            [C] = [C0 || C0 <- Channels, maps:with([source,port,tag,destination], C0) =:= Identity],
            Codec = hls_protocol_codec:plan(C, maps:get(source_operation,C)),
            maps:merge(#{index => Index, width => lists:nth(Index+1,Widths)}, Codec)
        end || #{index := Index, channel := Identity} <- Slots],
        (maps:with([index,slots,payload_bits], L))#{classes => SlotRows}
    end || L = #{widths := Widths, pair := #{slots := Slots}} <- Links],
    %% Keep only selector identities and codec permutations; compiler types are not JSON.
    CleanSources = [#{index => I, payload_width => Width, masks => Masks,
        outputs => [#{index => maps:get(index,O), rows => [maps:with(
            [layout,sequence,source_order,capture_slot],R) || R <- maps:get(rows,O)]}
            || O <- Outputs]} || #{index := I,payload_width := Width,masks := Masks,outputs := Outputs} <- Sources],
    CleanLinks = [maps:with([index,source_index,destination_index,output_index],L) || L <- Links],
    CleanBoundaries = [#{source => S, output => maps:get(index,O)} || #{source_index:=S,output:=O} <- Boundaries],
    file:write_file(filename:join(Directory,"witness.json"),json:encode(
        #{reference => Module,sources => CleanSources,links => CleanLinks,pairs => Pairs,boundaries => CleanBoundaries}),[exclusive]).
