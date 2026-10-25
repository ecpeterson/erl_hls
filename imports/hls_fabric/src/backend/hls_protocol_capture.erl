-module(hls_protocol_capture).
-moduledoc "Plans typed captures from complete compiler-owned actor programs. Capacity, receipt eligibility and network progress remain separate obligations.".
-export([plan/2]).

-doc "Joins every entry-effect layout across all phases of each internal producer's opaque compiler program. Omits only whole fields constant in every matching send; state-dependent and partially known fields stay whole. Rejects retained-call replies, whose sends are outside entry layouts. Programs must come from the same preparation as the actor emitters; no source reads or compilation occur here. Channel bindings are explicit caller input, not validated topology. Supplied alternatives or source/spec maps are not accepted; this does not admit mailbox replacement or network progress.".
-spec plan(#{channels := [map()], atom() => term()}, #{term() => xls_actor_program:program()}) -> map().
plan(#{channels := Channels}, Programs) ->
    Internal = [C || C = #{destination := {actor, _}} <- Channels],
    Producers = lists:usort([S || #{source := S} <- Internal]),
    Sources = maps:from_list([{S, source(maps:get(S, Programs))} || S <- Producers]),
    Rows = [begin
        #{alternatives := Entries, message_names := Names} = maps:get(S, Sources),
        Row = channel(C, [E || E = #{port := P, tag := T} <- Entries, P =:= Port, T =:= Tag]),
        [Op] = [N || {N, T} <- lists:enumerate(3, Names), T =:= Tag],
        Row#{source_operation => Op}
    end || C = #{source := S, port := Port, tag := Tag} <- Internal],
    #{channels => Rows, sources => maps:map(fun(_, #{provenance := P}) -> P end, Sources),
      storage => one_reserved_snapshot_per_static_channel,
      source_ownership => declared_producer_binding, overwrite => requires_consumer_release,
      generation_fields => retained_unless_source_constant,
      same_sender_cross_channel_order => requires_publication_and_receive_contract,
      network_progress => unestablished, eligible => false}.

%% Only the compiler constructor creates programs; there is no selected-alternative input.
-spec source(xls_actor_program:program()) -> map().
source(Program) ->
    #{source := File, retained_calls := Calls, message_names := Names} = xls_actor_program:spec(Program),
    case Calls of
        none -> ok;
        _ -> error({unsupported_capture_replies, File})
    end,
    Alternatives = [maps:with([phase, layout, order, port, tag, fields], Effect)
        || Effect <- xls_actor_program:entry_effects(Program)],
    #{alternatives => Alternatives, message_names => Names,
      provenance => xls_statem_plan:manifest(xls_actor_program:plan(Program))}.

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
