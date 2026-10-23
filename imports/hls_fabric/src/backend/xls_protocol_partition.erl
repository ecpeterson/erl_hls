-module(xls_protocol_partition).
-moduledoc "Elaborates canonical crossing codecs and named raw ports for a checked source partition. All behavioral control uses shared DSLX; this module supplies static wiring.".
-export([ports/1, write/2, fragments/1, name/1, files/1]).

-doc "Returns sampled crossing input/output fields grouped by direction, preserving global link order within each group. Incoming links expose ready/fault; outgoing links expose immutable slot/frame while valid. Each peer supplies the complementary handshake. No serial framing or clock crossing is provided.".
-spec ports(map()) -> {[{string(),pos_integer()}],[{string(),pos_integer()}]}.
ports(Plan) ->
    Incoming=[L||L=#{direction:=incoming}<-maps:get(crossings,Plan,[])],
    Outgoing=[L||L=#{direction:=outgoing}<-maps:get(crossings,Plan,[])],
    {lists:append([offer(I)||#{index:=I}<-Incoming])++[{name(I)++"_ready",1}||#{index:=I}<-Outgoing],
        lists:append([[{name(I)++"_ready",1},{name(I)++"_fault",1}]||#{index:=I}<-Incoming])++
        lists:append([offer(I)||#{index:=I}<-Outgoing])}.

-doc "Writes each source-bound crossing codec to an exclusive DSLX file beside transport.x. Requires the fresh partition planner's classes; generated logic validates header, padding and omitted constants and preserves every dynamic bit.".
-spec write(map(),file:filename()) -> ok.
write(Plan,Directory) ->
    lists:foreach(fun(#{index:=I,classes:=Classes})->lists:foreach(fun(#{slot:=K,codec:=Codec})->
        ok=hls_protocol_codec:write(Codec,"convert",filename:join(Directory,codec_name(I,K)++".x"))
    end,Classes) end,maps:get(crossings,Plan,[])),ok.

-doc "Returns DSLX imports, state fields, old-state views, next-state fields and output expressions for transport composition. Incoming canonical checks precede capture; outgoing frames restore destination schemas from held source projections. No additional payload state is introduced.".
-spec fragments(map()) -> map().
fragments(Plan) ->
    Cross=maps:get(crossings,Plan,[]),
    Incoming=[L||L=#{direction:=incoming}<-Cross],
    Imports=case Cross of []->[];_->["import protocol_partition as crossing_control;\n",
        [["import ",codec_name(I,K),";\n"]||#{index:=I,classes:=Cs}<-Cross,#{slot:=K}<-Cs]] end,
    #{imports=>Imports,
      state=>[[name(I),": crossing_control::State,\n"]||#{index:=I}<-Incoming],
      views=>[view(L)||L<-Cross],
      next=>[[name(I),": crossing_control::next(s.",name(I),", ",name(I),"_input),\n"]||#{index:=I}<-Incoming],
      values=>lists:append([values(L)||L<-Cross])}.

%% Canonical incoming projections are zero-extended to this pair's widest slot.
-spec view(map()) -> iodata().
view(#{index:=I,direction:=incoming,input_bits:=W,classes:=Classes}) ->
    R=name(I),
    ["let (",R,"_canonical, ",R,"_payload) = match io.",R,"_slot {\n",
     [["u8:",n(K)," => { let converted = ",codec_name(I,K),"::convert(io.",R,"_frame, bits[",n(P),"]:0, false, false, false, false);\n",
       "(converted.2, converted.0 as bits[",n(W),"]) },\n"]||#{slot:=K,codec:=#{physical_width:=P}}<-Classes],
     "_ => (false, bits[",n(W),"]:0), };\n",
     "let ",R,"_input = crossing_control::Inputs { reset: io.reset, valid: io.",R,"_valid, canonical: ",R,
     "_canonical, slot_ready: link_",n(I),".ready };\n",
     "let ",R," = crossing_control::observe(s.",R,", ",R,"_input);\n"];
view(#{index:=I,direction:=outgoing,source_index:=S,output_index:=D,output:=#{offset:=At,width:=W},classes:=Classes}) ->
    R=name(I),
    ["let ",R,"_slot = source_",n(S),".channel[",n(D*8),"+:u8];\n",
     "let ",R,"_payload = source_",n(S),".data[",n(At),"+:bits[",n(W),"]];\n",
     "let ",R,"_frame = match ",R,"_slot {\n",
     [["u8:",n(K)," => ",codec_name(I,K),"::convert(bits[128]:0, ",R,"_payload as bits[",n(P),"], false, false, false, false).1,\n"]
        ||#{slot:=K,codec:=#{physical_width:=P}}<-Classes],"_ => bits[128]:0, };\n"].

%% Transport observations are forwarded without another register or arbitration stage.
-spec values(map()) -> [{string(),iodata()}].
values(#{index:=I,direction:=incoming}) ->
    [{name(I)++"_"++K,name(I)++"."++K}||K<-["ready","fault"]];
values(#{index:=I,direction:=outgoing,source_index:=S,output_index:=D}) ->
    [{name(I)++"_valid",["source_",n(S),".valid[",n(D),"+:u1]"]},
     {name(I)++"_slot",name(I)++"_slot"},{name(I)++"_frame",name(I)++"_frame"}].

-doc "Lists generated codec paths relative to the network build for content binding before compilation.".
-spec files(map()) -> [string()].
files(Plan) -> ["dslx/"++codec_name(I,K)++".x"||#{index:=I,classes:=Cs}<-maps:get(crossings,Plan,[]),#{slot:=K}<-Cs].

-doc "Returns the stable sampled-port prefix for an original topology link index.".
-spec name(non_neg_integer()) -> string().
name(I) -> "remote_"++n(I).

%% Every offer has the same canonical frame width regardless of compact slot width.
-spec offer(non_neg_integer()) -> [{string(),pos_integer()}].
offer(I) -> [{name(I)++"_valid",1},{name(I)++"_slot",8},{name(I)++"_frame",128}].

%% One static codec per source-derived slot avoids any caller-selected schema.
-spec codec_name(non_neg_integer(),non_neg_integer()) -> string().
codec_name(I,K) -> name(I)++"_codec_"++n(K).

%% Only checked elaboration integers enter generated identifiers.
-spec n(non_neg_integer()) -> string().
n(I) -> integer_to_list(I).
