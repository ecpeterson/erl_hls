-module(xls_protocol_partition).
-moduledoc "Elaborates canonical crossing codecs and named raw ports for a checked source partition. All behavioral control uses shared DSLX; this module supplies static wiring.".
-export([ports/1, emit/1, write/2, wiring/1, name/1, files/1]).
-export_type([wiring/0]).

-doc "Retained crossing composition: declarations plus structured canonical-validation bindings, registered updates and pre-edge output expressions. Imports and state declarations depend only on checked codec/link identities.".
-type wiring() :: #{imports := iodata(), state := iodata(), views := [xls_dslx:binding()],
    next := [{string(), xls_dslx:expr()}], values := [{string(), xls_dslx:expr()}]}.

-doc "Returns sampled crossing input/output fields grouped by direction, preserving global link order within each group. Incoming links expose ready/fault and a per-class free mask; outgoing links expose immutable slot/frame while valid. Each peer supplies the complementary handshake. No serial framing or clock crossing is provided.".
-spec ports(map()) -> {[{string(),pos_integer()}],[{string(),pos_integer()}]}.
ports(Plan) ->
    FrameBits=hls_frame_layout:frame_bits(maps:get(frame_layout,Plan,hls_frame_layout:default())),
    Incoming=[L||L=#{direction:=incoming}<-maps:get(crossings,Plan,[])],
    Outgoing=[L||L=#{direction:=outgoing}<-maps:get(crossings,Plan,[])],
    {lists:append([offer(I,FrameBits)||#{index:=I}<-Incoming])++[{name(I)++"_ready",1}||#{index:=I}<-Outgoing],
        lists:append([[{name(I)++"_ready",1},{name(I)++"_fault",1},{name(I)++"_free",N}]||#{index:=I,slots:=N}<-Incoming])++
        lists:append([offer(I,FrameBits)||#{index:=I}<-Outgoing])}.

-doc "Writes each source-bound crossing codec to an exclusive DSLX file beside transport.x. Requires the fresh partition planner's classes; generated logic validates header, padding and omitted constants and preserves every dynamic bit.".
-spec write(map(),file:filename()) -> ok.
write(Plan, Directory) ->
    hls_generated_files:write_into(#{files => emit(Plan), result => ok}, Directory).

-doc "Returns named crossing codec files from the checked partition plan, with no output I/O. Names retain global link and class indices; duplicate filenames are rejected.".
-spec emit(map()) -> hls_generated_files:files().
emit(Plan) ->
    hls_generated_files:merge([#{codec_name(I, K) ++ ".x" => hls_protocol_codec:emit(Codec, "convert")}
        || #{index := I, classes := Classes} <- maps:get(crossings, Plan, []),
           #{slot := K, codec := Codec} <- Classes]).

-doc "Resolves crossing wiring from checked partition classes without rendering expressions. Incoming canonical validation precedes capture; outgoing frames restore schemas from held source projections. No payload register or arbitration stage is introduced.".
-spec wiring(hls_protocol_fabric:plan()) -> wiring().
wiring(Plan) ->
    Cross = maps:get(crossings, Plan, []),
    FrameBits=hls_frame_layout:frame_bits(maps:get(frame_layout,Plan,hls_frame_layout:default())),
    Incoming = [L || L = #{direction := incoming} <- Cross],
    Imports = case Cross of
        [] -> [];
        _ -> ["import protocol_partition as crossing_control;\n",
            [["import ", codec_name(I,K), ";\n"] || #{index := I, classes := Cs} <- Cross, #{slot := K} <- Cs]]
    end,
    #{imports => Imports,
      state => [[name(I), ": crossing_control::State,\n"] || #{index := I} <- Incoming],
      views => lists:append([view(L,FrameBits) || L <- Cross]),
      next => [{name(I), xls_dslx:call("crossing_control::next", [
          field("s", name(I)), ref(name(I)++"_input")])} || #{index := I} <- Incoming],
      values => lists:append([values(L) || L <- Cross])}.

%% Decode only the offered class, preserving canonical rejection before native capture.
-spec view(hls_protocol_partition:crossing(), pos_integer()) -> [xls_dslx:binding()].
view(#{index := I, direction := incoming, input_bits := W, classes := Classes}, _FrameBits) ->
    R = name(I),
    Arms = [{xls_dslx:literal("u8", K), xls_dslx:block([
        xls_dslx:bind("converted", xls_dslx:call(codec_name(I,K)++"::convert", [
            field("io", R++"_frame"), xls_dslx:literal({bits,P},0), ref("false"), ref("false"), ref("false"), ref("false")]))],
        xls_dslx:tuple([field("converted",2), xls_dslx:cast(field("converted",0), {bits,W})]))}
        || #{slot := K, codec := #{physical_width := P}} <- Classes],
    [xls_dslx:bind("("++R++"_canonical, "++R++"_payload)", xls_dslx:match(field("io", R++"_slot"),
        Arms++[{ref("_"), xls_dslx:tuple([ref("false"), xls_dslx:literal({bits,W},0)])}])),
     xls_dslx:bind(R++"_input", xls_dslx:construct("crossing_control::Inputs", [
        {"reset",field("io","reset")}, {"valid",field("io",R++"_valid")},
        {"canonical",ref(R++"_canonical")}, {"slot_ready",field("link_"++n(I),"ready")}])),
     xls_dslx:bind(R, xls_dslx:call("crossing_control::observe", [field("s",R),ref(R++"_input")]))];
view(#{index := I, direction := outgoing, source_index := S, output_index := D,
        output := #{offset := At, width := W}, classes := Classes}, FrameBits) ->
    R = name(I),
    [xls_dslx:bind(R++"_slot", xls_dslx:slice(field("source_"++n(S),"channel"),D*8,8)),
     xls_dslx:bind(R++"_payload", xls_dslx:slice(field("source_"++n(S),"data"),At,W)),
     xls_dslx:bind(R++"_frame", xls_dslx:match(ref(R++"_slot"),
        [{xls_dslx:literal("u8",K), xls_dslx:field(xls_dslx:call(codec_name(I,K)++"::convert", [
            xls_dslx:literal({bits,FrameBits},0), xls_dslx:cast(ref(R++"_payload"),{bits,P}),
            ref("false"),ref("false"),ref("false"),ref("false")]),1)}
            || #{slot := K, codec := #{physical_width := P}} <- Classes]++[{ref("_"),xls_dslx:literal({bits,FrameBits},0)}]))].

%% Remote outputs remain observations of held state; free credit cannot see this edge's release.
-spec values(hls_protocol_partition:crossing()) -> [{string(), xls_dslx:expr()}].
values(#{index := I, direction := incoming, slots := N}) ->
    R = name(I), L = "link_"++n(I),
    [{R++"_free", xls_dslx:choose(field("io","reset"), xls_dslx:literal({bits,N},0),
        xls_dslx:unary('!', xls_dslx:binary('|',field(L,"available"),field(L,"leased"))))}]++
    [{R++"_"++K,field(R,K)} || K <- ["ready","fault"]];
values(#{index := I, direction := outgoing, source_index := S, output_index := D}) ->
    R = name(I),
    [{R++"_valid",xls_dslx:slice(field("source_"++n(S),"valid"),D,1)},
     {R++"_slot",ref(R++"_slot")},{R++"_frame",ref(R++"_frame")}].

%% Local names remain structured until the final DSLX renderer.
-spec ref(string()) -> xls_dslx:expr().
ref(Name) -> xls_dslx:ref(Name).
%% Select a named struct field or an existing codec tuple position.
-spec field(string(), string() | non_neg_integer()) -> xls_dslx:expr().
field(Name, Member) -> xls_dslx:field(ref(Name), Member).

-doc "Lists generated codec paths relative to the network build for content binding before compilation.".
-spec files(map()) -> [string()].
files(Plan) -> ["dslx/"++codec_name(I,K)++".x"||#{index:=I,classes:=Cs}<-maps:get(crossings,Plan,[]),#{slot:=K}<-Cs].

-doc "Returns the stable sampled-port prefix for an original topology link index.".
-spec name(non_neg_integer()) -> string().
name(I) -> "remote_"++n(I).

%% Every offer has the same canonical frame width regardless of compact slot width.
-spec offer(non_neg_integer(), pos_integer()) -> [{string(),pos_integer()}].
offer(I,FrameBits) -> [{name(I)++"_valid",1},{name(I)++"_slot",8},{name(I)++"_frame",FrameBits}].

%% One static codec per source-derived slot avoids any caller-selected schema.
-spec codec_name(non_neg_integer(),non_neg_integer()) -> string().
codec_name(I,K) -> name(I)++"_codec_"++n(K).

%% Only checked elaboration integers enter generated identifiers.
-spec n(non_neg_integer()) -> string().
n(I) -> integer_to_list(I).
