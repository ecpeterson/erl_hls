-module(xls_protocol_inbox).
-moduledoc "Attaches receiver DSLX to a checked local-owner artifact during source transport emission. hls_protocol_inbox owns source analysis and slot layout; composition preserves the owner failure codebook while installing the corresponding capture-history logic.".

%% Receiver attachment to an emitted owner.
-export([attach/2]).

-doc "Renders the checked inbox around its matching owner artifact without source reads or layout analysis. Templates are read here; the owner and layout must originate from the same trusted transport build.".
-spec attach(hls_local_actor:artifact(), hls_protocol_inbox:layout()) -> hls_local_actor:artifact().
attach(Artifact = #{emitted := Emitted}, Layout) ->
    Metadata =
        #{
            frame_layout := FrameLayout,
            physical_slots := Count,
            mask_bits := N,
            cursor_bits := Cursor,
            host := #{slots := HostCount},
            startup := #{count := StartupCount, frames := Starts},
            inputs := Inputs,
            slots := Indexed,
            links := Links
        } = hls_protocol_inbox:descriptor(Layout),
    Completion = hls_protocol_inbox:completion(Layout),
    FrameBits = hls_frame_layout:frame_bits(FrameLayout),
    Host = HostCount =:= 1,
    Fields = [{binary_to_list(Name), Width} || #{name := Name, width := Width} <- Inputs],
    Path = filename:join(code:priv_dir(hls_lowering), "xls/templates/local_inbox.x.in"),
    {ok, Template} = file:read_file(Path),
    CompletionInputs =
        case Completion of
            local ->
                [];
            shared ->
                "completion_granted: io.completion_granted, completion_action: io.completion_action,"
        end,
    Inbox = xls_template:render(Template, [{<<"@@COMPLETION_INPUTS@@">>, CompletionInputs}]),
    Source = [
        xls_emitted:bytes(Emitted),
        "\nimport protocol_inbox as inbox_control;\nimport protocol_startup as startup_control;\n",
        "const INBOX_SLOTS = u32:",
        n(N),
        ";\nconst INBOX_CURSOR_BITS = u32:",
        n(Cursor),
        ";\n",
        "const CAPTURE_SLOTS = u32:",
        n(Count),
        ";\nconst STARTUP_BITS = u32:",
        n(max(1, StartupCount)),
        ";\n",
        "const STARTUP_VALID = bits[STARTUP_BITS]:",
        n((1 bsl StartupCount) - 1),
        ";\n",
        "// Clock input fields bind the exact incoming transport links.\npub struct LocalInboxInputs {\n",
        [
            [
                Name,
                ": ",
                case Name of
                    "completion_action" -> "LocalAction";
                    _ -> ["bits[", n(Width), "]"]
                end,
                ",\n"
            ]
         || {Name, Width} <- Fields
        ],
        "}\n",
        mask_function("selected", Links, N, Host, Count + StartupCount),
        mask_function("available", Links, N, Host, Count + StartupCount),
        "// Reconstruct the selected capture, startup or held host record as an ordinary destination frame.\n",
        "fn inbox_frame(io: LocalInboxInputs, index: u32) -> bits[",
        n(FrameBits),
        "] { match index {\n",
        [["u32:", n(I), " => ", frame(R), ",\n"] || R = #{index := I} <- Indexed],
        [
            ["u32:", n(Count + I), " => bits[", n(FrameBits), "]:0x", integer_to_list(F, 16), ",\n"]
         || {I, F} <- lists:enumerate(0, Starts)
        ],
        case Host of
            true -> ["u32:", n(Count + StartupCount), " => io.host_frame,\n"];
            false -> []
        end,
        "_ => bits[",
        n(FrameBits),
        "]:0, } }\n",
        Inbox
    ],
    Artifact#{
        emitted := xls_emitted:with_bytes(Emitted, iolist_to_binary(Source)), inbox => Metadata
    }.

%% Flatten metadata only; bit zero belongs to the first incoming pair's first slot.
-spec mask_function(
    string(),
    [#{index := non_neg_integer(), slots := pos_integer()}],
    pos_integer(),
    boolean(),
    non_neg_integer()
) -> iodata().
mask_function(Field, Links, N, Host, At) ->
    [
        "// Flatten the transport's ",
        Field,
        " mask in manifest slot order.\n",
        "fn inbox_",
        Field,
        "(io: LocalInboxInputs) -> bits[",
        n(N),
        "] { ",
        case Links of
            [] ->
                ["bits[", n(N), "]:0"];
            _ ->
                [
                    "(",
                    lists:join(" ++ ", [
                        ["io.", link_name(I), "_", Field]
                     || #{index := I} <- lists:reverse(Links)
                    ]),
                    ") as bits[",
                    n(N),
                    "]"
                ]
        end,
        case Host of
            true -> [" | ((io.host_valid as bits[", n(N), "]) << u32:", n(At), ")"];
            false -> []
        end,
        " }\n"
    ].

%% Codec constants and bit positions come from the checked current source channel.
-spec frame(hls_protocol_inbox:receiver_slot()) -> iodata().
frame(#{
    link := Link,
    payload_offset := At,
    codec := #{frame_layout := FrameLayout, value := Value, frame_positions := Positions}
}) ->
    Inverse = maps:from_list([{J, I} || {I, J} <- lists:enumerate(0, Positions)]),
    Bits = [
        case maps:find(J, Inverse) of
            {ok, I} -> {payload, At + I};
            error -> (Value bsr J) band 1
        end
     || J <- lists:seq(0, hls_frame_layout:frame_bits(FrameLayout) - 1)
    ],
    xls_protocol_bits:expression("io." ++ link_name(Link) ++ "_payloads", Bits).

%% Numeric names refer to the unchanged fabric link identities.
-spec link_name(non_neg_integer()) -> string().
link_name(I) -> "link_" ++ n(I).

%% Only elaborated dimensions and identities enter generated declarations.
-spec n(non_neg_integer()) -> string().
n(I) -> integer_to_list(I).
