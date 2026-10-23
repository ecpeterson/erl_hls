-module(hls_protocol_application_binding).
-moduledoc "Source-checked host codecs shared by single-device gateways and framed deployments. Descriptors are trusted local compiler outputs, never network terms.".
-export([bind/3, control/2, event/4]).

-doc "Checks loaded codecs against fresh source records and binds every actor to exactly one supplied device. Hosts supply positive 16-bit addresses. External schemas include only that device's actual producers. Returns typed rectangle and event bindings; transport identities and admission remain the caller's responsibility.".
-spec bind(map(),map(),map()) -> map().
bind(#{topology:=Topology=#{actors:=Actors,routes:=Routes,externals:=Externals},modules:=Modules},Owners,Hosts) ->
    true=lists:sort(maps:keys(Owners))=:=lists:sort([Id||#{id:=Id}<-Actors]),
    true=lists:sort(maps:keys(Hosts))=:=lists:usort(maps:values(Owners)),
    Interfaces=hls_actor_interface:from_modules(maps:keys(Modules)),
    maps:foreach(fun(M,A)->check_codec(M,A,maps:get(M,Interfaces)) end,Modules),
    ok=check_externals(Topology,Modules,Interfaces),
    Bound=[A#{identity=>{actor,Id},device=>maps:get(Id,Owners)}||A=#{id:=Id}<-Actors],
    Ingresses=hls_partition_ingress:lower(Topology,Bound,Interfaces),
    PortRoutes=[R#{source:={{actor,Id},Port}}||R=#{source:={Id,Port}}<-Routes],
    Ports=[E#{port=>"external_"++integer_to_list(I)}||{I,E}<-lists:enumerate(0,Externals)],
    Partition=#{actors=>Bound,routes=>PortRoutes,ingresses=>Ingresses},
    Devices=maps:map(fun(Device,Host)->
        Raw=hls_partition_wire:binding(Partition,Device,Host,#{ingresses=>Ingresses,externals=>Ports}),
        (maps:remove(identity,Raw))#{activation=>explicit_start}
    end,Hosts),
    #{partition=>Partition,devices=>Devices}.

-doc "Encodes a typed rectangle using the checked source schemas. All selected devices must share the same command bytes. The relay broadcasts those global bounds; each native sparse mask discards unowned targets. An empty selection or malformed command is rejected before queue admission.".
-spec control(map(),hls_partition_wire:command()) -> binary().
control(Application,Command) ->
    [Payload]=lists:usort([Bytes||{_,_,{2,0,0},Bytes}<-hls_partition_wire:command(Application,Command)]),
    Payload.

-doc "Decodes a canonical external frame at the emitted global endpoint index, using only the emitting device's producer schemas. Rejects unknown selectors, wrong word counts and noncanonical padding. This is codec validation, not application-semantic validation.".
-spec event(map(),term(),byte(),non_neg_integer()) -> {term(),tuple()}.
event(#{devices:=Devices},Device,Index,Frame) when Frame>=0,Frame<(1 bsl 128) ->
    Binding=#{host:=Host,events:=Events}=maps:get(Device,Devices),
    Port="external_"++integer_to_list(Index),
    [Endpoint]=[E||{E,#{port:=P}}<-maps:to_list(Events),P=:=Port],
    Words=Frame band 255,true=Words=<3,0=(Frame bsr 8) band 65535,
    Value=Frame bsr 32,true=Value<(1 bsl (Words*32)),Tag=(Frame bsr 24) band 255,
    hls_partition_wire:event(Binding,{Endpoint,Host},{Tag,0,0},<<Value:(Words*32)/little>>).

%% Field names/order, types, selectors and packed width must match fresh compiler records.
-spec check_codec(module(),map(),map()) -> ok.
check_codec(Module,#{spec:=#{message_names:=Names},plan:=#{records:=Records}},Interface) ->
    lists:foreach(fun({Op,Name})->
        #{selector:=Op,fields:=Fields}=hls_actor_interface:schema(Interface,Name),
        Op=Module:pack_tag(Name),
        [SourceFields]=[Fs||{attribute,_,record,{N,Fs}}<-Records,N=:=Name],
        Layout=[{element(3,element(3,F)),hls_type:descriptor(T)}||{typed_record_field,F,T}<-SourceFields],
        Layout=[{N,T}||#{name:=N,type:=T}<-Fields],
        Width=lists:sum([hls_type:width(T)||{_,T}<-Layout]),
        Width=Module:pack_width(Name)
    end,lists:enumerate(3,Names)).

%% A host event selector cannot ambiguously identify different producers' record layouts.
-spec check_externals(map(),map(),map()) -> ok.
check_externals(#{actors:=Actors,routes:=Routes,externals:=Externals},Modules,Interfaces) ->
    ById=maps:from_list([{Id,M}||#{id:=Id,module:=M}<-Actors]),
    lists:foreach(fun(#{id:=External})->
        Domains=lists:append([begin
            M=maps:get(Id,ById),Tags=hls_actor_interface:output_schemas(maps:get(M,Interfaces),Port),
            hls_protocol_schema:domains(maps:get(M,Modules),Tags)
        end||#{source:={Id,Port},recipients:=Recipients}<-Routes,lists:member({external,External},Recipients)]),
        _=lists:foldl(fun(D=#{value:=V},Seen)->
            Op=(V bsr 24) band 255,
            case maps:find(Op,Seen) of
                error->Seen#{Op=>D};
                {ok,D}->Seen;
                {ok,_}->error({ambiguous_application_event,External,Op})
            end
        end,#{},Domains),ok
    end,Externals).
