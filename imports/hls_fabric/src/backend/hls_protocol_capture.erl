-module(hls_protocol_capture).
-moduledoc "Plans typed capture layouts from freshly compiled actor sources. This component does not establish channel capacity, receipt eligibility or network progress.".
-export([plan/2]).
-export_type([source/0]).

-doc "An actor's source file and ordinary preprocessing options. Supplied alternatives, inferred state constants and saved compiler artifacts are not accepted.".
-type source() :: #{file := file:filename(), options := [hls_source:option()] | hls_source:context()}.

-doc "Compiles each internal producer and joins every ordinary entry-effect layout across all phases for each requested port/tag. Omits only whole-field constants established by ordinary lowering in every matching send; state-dependent and partially known fields stay whole. Rejects missing sends and actors with retained-call replies, whose sends are outside entry layouts. Channel bindings are explicit caller input, not a validated topology. No mailbox replacement or connected-protocol eligibility is granted.".
-spec plan(#{channels := [map()], atom() => term()}, #{term() => source()}) -> map().
plan(#{channels := Channels}, Sources) ->
    Internal = [C || C = #{destination := {actor, _}} <- Channels],
    Producers = lists:usort([S || #{source := S} <- Internal]),
    Compiled = maps:from_list([{S, compile(maps:get(S, Sources))} || S <- Producers]),
    Rows = [begin
        #{alternatives := Entries, message_names := Names} = maps:get(S, Compiled),
        Row = channel(C, [E || E = #{port := P, tag := T} <- Entries, P =:= Port, T =:= Tag]),
        [Op] = [N || {N, T} <- lists:enumerate(3, Names), T =:= Tag],
        Row#{source_operation => Op}
    end || C = #{source := S, port := Port, tag := Tag} <- Internal],
    #{channels => Rows, sources => maps:map(fun(_, #{provenance := P}) -> P end, Compiled),
      storage => one_reserved_snapshot_per_static_channel,
      source_ownership => declared_producer_binding, overwrite => requires_consumer_release,
      generation_fields => retained_unless_source_constant,
      same_sender_cross_channel_order => requires_publication_and_receive_contract,
      network_progress => unestablished, eligible => false}.

%% Compile all phases together: callers cannot select a favorable branch or supply stale constant facts.
-spec compile(source()) -> map().
compile(#{file := File, options := Options}) ->
    {Spec, Plan} = xls_statem_plan:from_file(File, Options),
    case maps:get(retained_calls, Spec) of
        none -> ok;
        _ -> error({unsupported_capture_replies, File})
    end,
    #{entries := Entries, message_names := Names} = Spec,
    Alternatives = [#{phase => Phase, layout => Layout, order => Order,
        port => Port, tag => Tag, fields => Fields}
        || #{layouts := Layouts} <- Entries,
           #{phase := Phase, layout := Layout, storage := #{effects := Effects}} <- Layouts,
           {Order, #{port := Port, tag := Tag, fields := Fields}} <- lists:enumerate(0, Effects)],
    #{alternatives => Alternatives, message_names => Names,
      provenance => xls_statem_plan:manifest(Plan)}.

%% The complete family determines constants; a convenient single phase cannot stand for all sends.
-spec channel(map(),[map()]) -> map().
channel(C,[First|_]=Alternatives) ->
    Signature=[maps:with([name,type],F) || F<-maps:get(fields,First)],
    true=lists:all(fun(#{fields:=Fs})->[maps:with([name,type],F)||F<-Fs]=:=Signature end,Alternatives),
    {Fields,{OriginalBits,StoredBits}}=lists:mapfoldl(fun(F,{Wire,At})->
        Width=hls_type:width(maps:get(type,F)),
        Joined=join(F,Alternatives),
        case Joined of
            #{constant:=_}->{Joined#{message_bit_offset=>Wire},{Wire+Width,At}};
            _->{Joined#{message_bit_offset=>Wire,capture_bit_offset=>At},{Wire+Width,At+Width}}
        end
    end,{0,0},Signature),
    (maps:with([source,port,tag,destination],C))#{fields=>Fields,
      message_bits=>OriginalBits,payload_bits=>StoredBits,parameters=>#{width=>max(1,StoredBits)},
      writer_count=>1,reader_count=>1,snapshot_slots=>1,capacity_bound=>unestablished,
      source_alternatives_hash=>hash(Alternatives)};
channel(C,[]) -> error({missing_channel_alternatives,maps:with([source,port,tag,destination],C)}).

%% Partial facts are intentionally retained as full fields until a lossless field codec is qualified.
-spec join(map(),[map()]) -> map().
join(F=#{name:=Name,type:=Type},Alternatives) ->
    Values=[maps:find(constant,hd([X||X=#{name:=N}<-Fields,N=:=Name]))
        || #{fields:=Fields}<-Alternatives],
    case lists:usort(Values) of
        [{ok,Bits}] -> true=bit_size(Bits)=:=hls_type:width(Type),F#{constant=>Bits};
        _ -> F
    end.

%% The digest identifies the joined alternatives; it is not an independent correctness certificate.
-spec hash(term()) -> binary().
hash(Term) -> binary:encode_hex(crypto:hash(sha256,term_to_binary(Term,[deterministic])),lowercase).
