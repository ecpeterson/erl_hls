-module(hls_protocol_observation).
-moduledoc "Binds fixed protocol owners to the common scheduler inspection API. Queries are passive coherent snapshots, not mailbox histories or event traces.".
-export([open/2, catalog/2]).

-doc "Verifies an endpoint-2 debug session against the diagnostic build manifest. Returns transport or fingerprint errors without weakening manifest checks. Process-scoped manifests use the actor-only INFO form and the unchanged shared query/observation decoder.".
-spec open(pid(), map()) -> {ok, map()} | {error, term()}.
open(Client, Manifest=#{<<"inspection">>:=#{<<"scope">>:=<<"process">>}}) ->
    process_session(Client,Manifest);
open(Client, Manifest) -> hls_topology_debug:open(Client, Manifest).

%% The shared schema supports zero channels; the inherited generic opener requires
%% at least one. Keep the same session/query decoder while validating actor-only INFO.
-spec process_session(pid(),map()) -> {ok,map()} | {error,term()}.
process_session(Client,Manifest) ->
    case hls_debug:query(Client,16#10,<<>>,10000) of
      {ok,<<5:32/little,Count:32/little,0:32/little,0:32/little,
          Count:32/little,Raw:32/binary>>} when Count>0 ->
        case Manifest of
          #{<<"schema">>:=5,<<"fingerprint">>:=Hash,<<"resources">>:=Resources,
            <<"probes">>:=[]} when length(Resources)=:=Count ->
            Valid=binary:encode_hex(Raw,lowercase)=:=Hash andalso
              hls_topology_debug:manifest_fingerprint(Manifest)=:=Hash andalso
              [maps:get(<<"id">>,R)||R<-Resources]=:=lists:seq(0,Count-1) andalso
              lists:all(fun(#{<<"kind">>:=<<"actor">>})->true;(_)->false end,Resources),
            case Valid of
              true->{ok,#{client=>Client,manifest=>Manifest,resources=>list_to_tuple(Resources)}};
              false->{error,corrupt_topology_manifest}
            end;
          _->{error,topology_manifest_mismatch}
        end;
      {ok,_}->{error,unsupported_process_info};
      {error,_}=Error->Error
    end.

-doc "Binds the trusted local network/inspection.etf catalog to a verified session from open/2. Checks the catalog identity before exposing logical actor targets through hls_debug:info. ETF is trusted local build data, never network input; its finite phase/failure/collection names are interned for the shared actor decoder even when actor modules are absent. Snapshot fields include committed phase/failure and collection metadata; mailbox counts and traces remain unavailable.".
-spec catalog(map(),map()) -> map().
catalog(#{actors:=Actors,manifest:=Manifest},Session=#{manifest:=Manifest}) ->
    #{<<"catalogue_sha256">>:=Hash,<<"fingerprint">>:=Fingerprint,<<"resources">>:=Resources}=Manifest,
    Hash=binary:encode_hex(crypto:hash(sha256,term_to_binary(Actors,[deterministic])),lowercase),
    true=lists:sort([I||#{index:=I}<-Actors])=:=lists:seq(0,length(Resources)-1),
    Targets=[begin
        [Resource=#{<<"owner_index">>:=I,<<"id">>:=I,<<"role">>:=Role,<<"logical_key">>:=Key}]=[R||R=#{<<"id">>:=J}<-Resources,J=:=I],
        Role=atom_to_binary(M,utf8),Key=xls_actor_debug:actor_key(Id),
        ok=codebook(Resource),
        Identity={actor,Id},
        {Identity,{actor,#{identity=>Identity,module=>M,
            scope=>#{kind=>actor,backend=>hardware,id=>Identity},boundaries=>[],
            placement=>#{kind=>protocol_owner,index=>I},
            observation=>#{kind=>committed_state,mailbox=>unavailable,fingerprint=>Fingerprint,resource=>I}},
            {actor_snapshot,Session,I}}}
    end||#{index:=I,id:=Id,module:=M}<-Actors],
    true=length(Targets)=:=length(Resources),
    true=length(Targets)=:=length(lists:usort([Id||{Id,_}<-Targets])),
    #{actors=>maps:from_list(Targets),boundaries=>[]}.


%% Only the fingerprint-bound trusted local catalog supplies atoms; wire replies carry indices.
-spec codebook(map()) -> ok.
codebook(#{<<"phases">>:=Phases,<<"failures">>:=Failures}=Resource) ->
    Sites=maps:get(<<"sites">>,maps:get(<<"reduction">>,Resource,#{}),[]),
    Names=Phases++[K||#{<<"kind">>:=K}<-maps:values(Failures)]++
        lists:append([[N,P]||#{<<"name">>:=N,<<"phase">>:=P}<-Sites]),
    _= [binary_to_atom(N,utf8)||N<-lists:usort(Names)],ok.
