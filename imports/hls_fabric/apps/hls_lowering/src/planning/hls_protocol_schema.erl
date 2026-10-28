-module(hls_protocol_schema).
-moduledoc "Binds startup values and host frame domains to fresh receiving-actor schemas. Inbox, control and application-binding planners share these canonical constraints; source callbacks still own semantic validation of admitted payloads.".

%% Startup encoding and receiver domains.
-export([frames/2, domains/2]).

-doc "Encodes startup records in declared sender order, including duplicates. Requires the receiving hls_local_actor source snapshot from the same fresh source build. Checks record identity/arity and exact host packing, then uses the canonical frame layout retained by its compiler program. Supports built-in numeric/boolean codecs and full-width integer bit-cast providers; other codecs raise schema diagnostics. Source callbacks still determine consume, postpone or failure. This is not a startup progress proof.".
-spec frames(hls_local_actor:source() | hls_local_actor:artifact(), [tuple()]) ->
    [non_neg_integer()].
frames(#{program := Program}, Messages) ->
    #{message_names := Names, frame_layout := FrameLayout} = xls_actor_program:spec(Program),
    Records = xls_statem_plan:records(xls_actor_program:plan(Program)),
    [frame(Message, Names, Records, FrameLayout) || Message <- Messages].

-doc "Returns canonical mask/value domains for a nonempty list of declared message tags. Uses the complete ordinary header and zero padding, leaving every represented payload value arbitrary. Also binds ordered field names and exact provider/type descriptors, so equal masks cannot hide incompatible record layouts. Requires the same checked source snapshot as the receiving actor. Unsupported codecs, duplicate/unknown tags and payloads beyond the selected frame capacity reject; invalid tags and unsupported codecs raise schema diagnostics; semantic invalid values must still reach the source callback.".
-spec domains(hls_local_actor:source() | hls_local_actor:artifact(), [atom()]) -> [map()].
domains(#{program := Program}, Tags) ->
    #{message_names := Names, frame_layout := FrameLayout} = xls_actor_program:spec(Program),
    Records = xls_statem_plan:records(xls_actor_program:plan(Program)),
    case Tags =/= [] andalso length(Tags) =:= length(lists:usort(Tags)) of
        true ->
            ok;
        false ->
            hls_diagnostic:raise(
                schema,
                invalid_ingress_schemas,
                <<"An ingress target needs a nonempty list of distinct message tags.">>,
                #{schemas => Tags}
            )
    end,
    [
        case
            {[I || {I, T} <- lists:enumerate(3, Names), T =:= Tag], [
                Fs
             || {attribute, _, record, {T, Fs}} <- Records, T =:= Tag
            ]}
        of
            {[Op], [Fields]} ->
                (maps:with(
                    [mask, value],
                    xls_message_bits:frame(
                        Op,
                        [#{type => field_type(F), domain => unknown} || F <- Fields],
                        FrameLayout
                    )
                ))#{
                    tag => Tag, schema_sha256 => schema_hash(Fields)
                };
            _ ->
                hls_diagnostic:raise(
                    schema,
                    undeclared_protocol_schema,
                    <<"An ingress message tag must be declared by its receiving actor.">>,
                    #{schema => Tag, declared_schemas => Names}
                )
        end
     || Tag <- Tags
    ].

%% Ignore source locations/default expressions, but bind ordered names and exact codec types.
-spec schema_hash([term()]) -> binary().
schema_hash(Fields) ->
    Layout = [
        begin
            {atom, _, Name} = element(3, Field),
            {Name, field_type(F)}
        end
     || F = {typed_record_field, Field, _} <- Fields
    ],
    binary:encode_hex(crypto:hash(sha256, term_to_binary(Layout, [deterministic])), lowercase).

%% Match the receiving module's tag enumeration and typed record field order exactly.
-spec frame(tuple(), [atom()], [term()], hls_frame_layout:layout()) -> non_neg_integer().
frame(Message, Names, Records, FrameLayout) when is_tuple(Message), tuple_size(Message) > 0 ->
    [Tag | Values] = tuple_to_list(Message),
    case
        {[I || {I, T} <- lists:enumerate(3, Names), T =:= Tag], [
            Fs
         || {attribute, _, record, {T, Fs}} <- Records, T =:= Tag
        ]}
    of
        {[Op], [Fields]} when length(Values) =:= length(Fields) ->
            Bound = [
                #{type => Type, domain => {values, [hls_type:pack_exact(V, Type)]}}
             || {V, Type} <- lists:zip(Values, [field_type(F) || F <- Fields])
            ],
            #{mask := Mask, value := Value} = xls_message_bits:frame(Op, Bound, FrameLayout),
            true = Mask =:= (1 bsl hls_frame_layout:frame_bits(FrameLayout)) - 1,
            Value;
        _ ->
            invalid_startup(Message, Names)
    end;
frame(Message, Names, _, _) ->
    invalid_startup(Message, Names).

%% Startup is source input; wrong record identity or arity is not a compiler invariant failure.
-spec invalid_startup(term(), [atom()]) -> no_return().
invalid_startup(Message, Names) ->
    hls_diagnostic:raise(
        schema,
        invalid_startup_record,
        <<"A startup value must be a declared message record with the exact field count.">>,
        #{message => Message, declared_schemas => Names}
    ).

%% Admit only codecs with the established ordinary scalar wire representation.
-spec field_type(term()) -> hls_type:descriptor().
field_type({typed_record_field, _, Type}) ->
    Descriptor = hls_type:descriptor(Type),
    case Descriptor of
        {hls_type, P, _, _} when P =:= hls_nums; P =:= hls_bool -> Descriptor;
        _ -> wire_scalar(Descriptor)
    end.

%% A provider may validate values, but may not hide padding or custom wire transforms.
-spec wire_scalar(hls_type:descriptor()) -> hls_type:descriptor().
wire_scalar(Descriptor) ->
    Printed = iolist_to_binary(xls_type:print_type(Descriptor)),
    Width = hls_type:width(Descriptor),
    case
        {
            xls_type:dslx_codec(Descriptor),
            re:run(Printed, "^[us]([1-9][0-9]*)$", [{capture, [1], binary}])
        }
    of
        {bit_cast, {match, [Bits]}} when Width > 0 ->
            case
                binary_to_integer(Bits) =:= Width andalso hls_type:value_width(Descriptor) =:= Width
            of
                true -> Descriptor;
                false -> unsupported_codec(Descriptor)
            end;
        _ ->
            unsupported_codec(Descriptor)
    end.

%% Custom providers must expose the scalar bit-cast ABI required by ordinary protocol frames.
-spec unsupported_codec(hls_type:descriptor()) -> no_return().
unsupported_codec(Descriptor) ->
    hls_diagnostic:raise(
        schema,
        unsupported_protocol_schema_codec,
        <<"Protocol fields require a supported numeric/boolean codec or a full-width scalar bit-cast provider.">>,
        #{type => Descriptor}
    ).
