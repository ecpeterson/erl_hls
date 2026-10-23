-module(hls_protocol_inbox).
-moduledoc "Groups typed capture channels by logical sender and destination. Per-pair delivery precedence preserves selective receive without inventing cross-sender chronology.".
-export([plan/1, attach/5]).

-doc "Plans independent sender/destination histories over exact typed capture channels. Channels from distinct ports of one sender share a history; separate senders do not. Each pending channel currently has one slot, so a repeated send must wait for its lease to be released. This establishes neither sufficient application capacity nor transport deadlock freedom; whole-protocol eligibility remains false.".
-spec plan(map()) -> map().
plan(#{channels:=Channels}) ->
    Groups=lists:foldl(fun(C=#{source:=Source,destination:=Destination},Acc)->
        maps:update_with({Source,Destination},fun(Cs)->[C|Cs] end,[C],Acc)
    end,#{},Channels),
    #{pairs=>[pair(Key,Cs)||{Key,Cs}<-lists:sort(maps:to_list(Groups))],
      cross_sender_chronology=>none,selection=>oldest_eligible_within_logical_sender,
      postponed_message=>retained_without_blocking_later_eligible_message,
      leased_payload=>held_separately_until_consumer_release,
      capacity=>unestablished,network_progress=>unestablished,eligible=>false}.

%% Every physical channel has a stable identity; duplicate routes cannot create alias slots.
-spec pair({term(),term()},[map()]) -> map().
pair({Source,Destination},Channels) ->
    Keys=[{maps:get(port,C),maps:get(tag,C)}||C<-Channels],
    case length(Keys)=:=length(lists:usort(Keys)) of
        true->ok;false->error({duplicate_capture_channel,Source,Destination})
    end,
    Ordered=lists:keysort(1,lists:zip(Keys,Channels)),
    #{source=>Source,destination=>Destination,
      slots=>[#{index=>I,channel=>maps:with([source,port,tag,destination],C),
          payload_bits=>maps:get(payload_bits,C)}||{I,{_,C}}<-lists:enumerate(0,Ordered)],
      parameters=>#{slots=>length(Channels)},
      arrival_contract=>one_accepted_message_per_clock_in_sender_order,
      reuse_contract=>capture_credit_and_absent_pending_message}.

-doc "Attaches the ordinary inbox plus exact declared startup records to a fresh source artifact. Startup records are constant slots after the capture slots, ordered as one additional logical sender. They remain pending through reservation/postponement, retire only on source consume, and replay after shared reset. An addressed host adds one final slot; host_valid/frame must remain immutable until source consume, including through postponement. Total capture, startup and host slots must not exceed 256. The same source schema supplies startup encoding; no caller-supplied frames or startup progress assumptions are accepted.".
-spec attach(hls_local_actor:artifact(), [map()], map(), [tuple()], boolean()) -> hls_local_actor:artifact().
attach(Artifact=#{spec:=#{message_names:=Names},dslx:=Body}, Links, #{channels:=Channels}, Messages, Host) ->
    Starts=hls_protocol_schema:frames(Artifact,Messages),
    Rows=lists:append([[begin
        [Op]=[N||{N,T}<-lists:enumerate(3,Names),T=:=maps:get(tag,C)],
        [Channel]=[Ch||Ch<-Channels,maps:with([source,destination,port,tag],Ch)=:=C],
        #{link=>I,slot=>K,width=>lists:nth(K+1,Widths),
          payload_offset=>lists:sum(lists:sublist(Widths,K)),
          codec=>hls_protocol_codec:plan(Channel,Op)}
    end||#{index:=K,channel:=C}<-Slots]
    ||#{index:=I,widths:=Widths,pair:=#{slots:=Slots}}<-Links]),
    Count=length(Rows), StartupCount=length(Starts), HostCount=case Host of true->1;false->0 end, Total=Count+StartupCount+HostCount,
    case Total=<256 of true->ok;false->error({inbox_slot_limit,Total,256}) end,
    N=max(1,Total), Cursor=max(1,ceil(math:log2(N))),
    Indexed=[R#{index=>I}||{I,R}<-lists:enumerate(0,Rows)],
    Fields=[{"reset",1},{"output_ready",1}]++(case Host of true->[{"host_valid",1},{"host_frame",128}];false->[] end)++lists:append([
        [{link_name(I)++"_selected",S},{link_name(I)++"_available",S},
         {link_name(I)++"_payloads",W}]||#{index:=I,slots:=S,payload_bits:=W}<-Links]),
    {ok,Template}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/templates/local_inbox.x.in")),
    Source=[Body,"\nimport protocol_inbox as inbox_control;\nimport protocol_startup as startup_control;\n",
        "const INBOX_SLOTS = u32:",n(N),";\nconst INBOX_CURSOR_BITS = u32:",n(Cursor),";\n",
        "const CAPTURE_SLOTS = u32:",n(Count),";\nconst STARTUP_BITS = u32:",n(max(1,StartupCount)),";\n",
        "const STARTUP_VALID = bits[STARTUP_BITS]:",n((1 bsl StartupCount)-1),";\n",
        "// Clock input fields bind the exact incoming transport links.\npub struct LocalInboxInputs {\n",
        [[Name,": bits[",n(Width),"],\n"]||{Name,Width}<-Fields],"}\n",
        mask_function("selected",Links,N,Host,Count+StartupCount),mask_function("available",Links,N,Host,Count+StartupCount),
        "// Reconstruct the selected capture, startup or held host record as an ordinary destination frame.\n",
        "fn inbox_frame(io: LocalInboxInputs, index: u32) -> bits[128] { match index {\n",
        [["u32:",n(I)," => ",frame(R),",\n"]||R=#{index:=I}<-Indexed],
        [["u32:",n(Count+I)," => bits[128]:0x",integer_to_list(F,16),",\n"]||{I,F}<-lists:enumerate(0,Starts)],
        case Host of true-> ["u32:",n(Count+StartupCount)," => io.host_frame,\n"];false->[] end,
        "_ => bits[128]:0, } }\n",Template],
    Artifact#{dslx:=iolist_to_binary(Source),inbox=>#{physical_slots=>Count,mask_bits=>N,
        cursor_bits=>Cursor,additional_state_bits=>3*N+Cursor+1+StartupCount,
        host=>#{slots=>HostCount,offset=>Count+StartupCount,retirement=>source_consume},
        startup=>#{count=>StartupCount,offset=>Count,frames=>Starts,
            order=>oldest_eligible_declared_record,retirement=>source_consume,reset=>replay},
        inputs=>[#{name=>list_to_binary(K),width=>W}||{K,W}<-Fields],
        slots=>Indexed,links=>[maps:with([index,slots],L)||L<-Links],
        selected_head=>pending_until_consumed,release=>one_clock_after_consume,
        phase_boundary=>wakes_all_postponed,ordering=>per_logical_sender_destination,
        capacity=>unestablished,network_progress=>unestablished}}.

%% Flatten metadata only; bit zero belongs to the first incoming pair's first slot.
-spec mask_function(string(),[map()],pos_integer(),boolean(),non_neg_integer()) -> iodata().
mask_function(Field,Links,N,Host,At) ->
    ["// Flatten the transport's ",Field," mask in manifest slot order.\n",
     "fn inbox_",Field,"(io: LocalInboxInputs) -> bits[",n(N),"] { ",
     case Links of []->["bits[",n(N),"]:0"];
         _->["(",lists:join(" ++ ",[["io.",link_name(I),"_",Field]||#{index:=I}<-lists:reverse(Links)]),") as bits[",n(N),"]"] end,case Host of true->[" | ((io.host_valid as bits[",n(N),"]) << u32:",n(At),")"];false->[] end," }\n"].

%% Codec constants and bit positions come from the checked current source channel.
-spec frame(map()) -> iodata().
frame(#{link:=Link,payload_offset:=At,codec:=#{value:=Value,frame_positions:=Positions}}) ->
    Inverse=maps:from_list([{J,I}||{I,J}<-lists:enumerate(0,Positions)]),
    lists:join(" ++ ",[case maps:find(J,Inverse) of
        {ok,I}->["io.",link_name(Link),"_payloads[",n(At+I),"+:u1]"];
        error->["u1:",n((Value bsr J) band 1)] end||J<-lists:seq(127,0,-1)]).

%% Numeric names refer to the unchanged fabric link identities.
-spec link_name(non_neg_integer()) -> string().
link_name(I) -> "link_"++n(I).

%% Only elaborated dimensions and identities enter generated declarations.
-spec n(non_neg_integer()) -> string().
n(I) -> integer_to_list(I).
