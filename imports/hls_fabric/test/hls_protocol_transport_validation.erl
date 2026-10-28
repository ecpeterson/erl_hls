-module(hls_protocol_transport_validation).
-moduledoc "Prepares independent ordinary-decoder references for the production transport output.".
-export([prepare/1, startup/1, ingress/1]).
-doc "Reads a fresh trusted local transport build, writes ordinary DSLX effect decoders and a finite-witness catalogue. The RTL scoreboard uses these ordinary decoders, not the publisher's bit projection, to check frames. This is test preparation, not application admission.".
-spec prepare(file:filename()) -> ok.
prepare(Directory) ->
    {ok, Bytes} = file:read_file(filename:join(Directory, "transport.etf")),
    #{bundle := #{modules := Modules}, sources := #{sources := Sources},
      capture := #{channels := Channels}, fabric := #{links := Links, boundaries := Boundaries}} = binary_to_term(Bytes),
    [{Module, #{program := Program}}] = maps:to_list(Modules),
    Spec = xls_actor_program:spec(Program),
    ok = file:write_file(filename:join(Directory, "reference.x"), xls_activation_codegen:emit(Spec), [exclusive]),
    Pairs = [begin
        SlotRows = [begin
            [C] = [C0 || C0 <- Channels, maps:with([source,port,tag,destination], C0) =:= Identity],
            Codec = hls_protocol_codec_plan:plan(C, maps:get(source_operation,C)),
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

-doc "Checks every fixed startup frame in a fresh trusted transport build against the receiving module's ordinary BEAM pack/pack_tag functions. Recompiles those exact recorded source contexts, compares duplicate-preserving lists for all actors, and retains the reference frames. This is a finite host-codec witness, not source progress or DSLX equivalence.".
-spec startup(file:filename()) -> ok.
startup(Directory) ->
    {ok,Bytes}=file:read_file(filename:join(Directory,"transport.etf")),
    #{bundle:=#{topology:=#{actors:=Actors,startup:=Startup},modules:=Modules},receivers:=Receivers}=binary_to_term(Bytes),
    maps:foreach(fun(M,#{context:=Context=#{source_name:=File}}) ->
        Forms=hls_source:read(File,Context),
        {ok,M,Code}=compile:forms(Forms,[binary,debug_info,warnings_as_errors,report]),
        {module,M}=code:load_binary(M,File,Code)
    end,Modules),
    Rows=[begin
        Messages=lists:append([Ms||#{target:=Target,messages:=Ms}<-Startup,Target=:=Id]),
        Expected=[ordinary_frame(M,Message)||Message<-Messages],
        [#{manifest:=#{inbox:=#{startup:=#{frames:=Actual}}}}]=[R||R=#{index:=J}<-Receivers,J=:=I],
        Expected=Actual,
        #{actor=>iolist_to_binary(io_lib:format("~p",[Id])),index=>I,frames=>Expected}
    end||{I,#{id:=Id,module:=M}}<-lists:enumerate(0,Actors)],
    file:write_file(filename:join(Directory,"startup-reference.json"),json:encode(#{actors=>Rows}),[exclusive]).

-doc "Checks a fresh trusted transport build's host domains against ordinary BEAM zero-valued record packing and independently normalized recipient coordinates. Checks every target/recipient binding, including collocated actors, and retains the finite reference catalogue. Does not establish runtime semantics or application progress.".
-spec ingress(file:filename()) -> ok.
ingress(Directory) ->
    {ok,Bytes}=file:read_file(filename:join(Directory,"transport.etf")),
    #{bundle:=#{topology:=#{actors:=Actors,ingresses:=Ingresses},modules:=Modules},ingress:=Plan,receivers:=Receivers}=binary_to_term(Bytes),
    maps:foreach(fun(M,#{context:=Context=#{source_name:=File}}) ->
        {ok,M,Code}=compile:forms(hls_source:read(File,Context),[binary,debug_info,warnings_as_errors,report]),
        {module,M}=code:load_binary(M,File,Code)
    end,Modules),
    Rows=case Plan of
      none -> [];
      #{targets:=Targets} ->
        [#{targets:=Declared}]=Ingresses,
        [begin
          [#{schemas:=Schemas,recipients:=Expected}]=[T||T=#{id:=Name}<-Declared,Name=:=Id],
          true=lists:sort(Schemas)=:=lists:sort([Tag||#{tag:=Tag}<-Domains]),
          Actual=[begin
            #{id:=Actor,module:=M}=lists:nth(I+1,Actors),
            #{program:=Program}=maps:get(M,Modules),
            Records=xls_statem_plan:records(xls_actor_program:plan(Program)),
            lists:foreach(fun(#{tag:=Tag,mask:=Mask,value:=Value})->
              [Fs]=[Fields||{attribute,_,record,{Name,Fields}}<-Records,Name=:=Tag],
              Message=list_to_tuple([Tag|[hls_type:zero(hls_type:descriptor(Type))||{typed_record_field,_,Type}<-Fs]]),
              Frame=ordinary_frame(M,Message),Value=Frame band Mask
            end,Domains),
            #{actor=>Actor,at=>[X,Y]}
          end||#{index:=I,x:=X,y:=Y}<-Points],
          true=lists:sort(Actual)=:=lists:sort(Expected),
          #{selector=>Selector,recipients=>length(Actual),schemas=>length(Domains)}
        end||#{id:=Id,selector:=Selector,domains:=Domains,recipients:=Points}<-Targets]
    end,
    lists:foreach(fun(#{index:=I,manifest:=#{inbox:=#{host:=#{slots:=N}}}})->
        N=case hls_protocol_control:addressed(Plan,I) of true->1;false->0 end
    end,Receivers),
    file:write_file(filename:join(Directory,"ingress-reference.json"),json:encode(#{targets=>Rows}),[exclusive]).

%% The ordinary host packer supplies the physical stream and schema tag independently.
-spec ordinary_frame(module(),tuple()) -> non_neg_integer().
ordinary_frame(M,Message) ->
    Tag=M:pack_tag(element(1,Message)),Stream=M:pack(Message),N=bit_size(Stream),
    true=N=<96,<<Payload:96/little>> = <<Stream/bitstring,0:(96-N)>>,
    (Payload bsl 32) bor (Tag bsl 24) bor ((N+31) div 32).
