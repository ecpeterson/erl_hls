-module(xls_exclusive_collection_codegen).
-moduledoc "Renders an early collector under an explicit exclusive, nonoverlapping-epoch contract. Direct and scheduled collection renderers reuse its declarations and source fragments after validation; this policy is not inferred from arbitrary traffic.".

%% Policy validation and actor specialization.
-export([validate/1, actor_spec/1]).

%% Collector DSLX declarations and implementation.
-export([declarations/1, helpers/1, core/1]).

-doc "Requires one member-based site with message-only contribution expressions; protocol exclusivity remains an unchecked assertion.".
-spec validate(map()) -> ok.
validate(#{sites := [#{population := #{mode := members}}]} = Reduction) ->
    _ = xls_reduction_codegen:transport_function(Reduction, exclusive_epoch),
    logger:warning(
        "exclusive_epoch asserts exclusive message ownership, a commutative monoid, and no interleaved keys while collection is incomplete; these protocol properties are not compile-time checked"
    ),
    ok;
validate(_) ->
    error(exclusive_epoch_requires_one_member_site).

-doc "Defines the common keyed ownership interface for selected direct or shared collectors.".
-spec declarations(map()) -> iodata().
declarations(Spec) ->
    case
        maps:get(admission_reductions, Spec, false) == exclusive_epoch orelse
            maps:get(direct_collection, Spec, false) == exclusive_epoch
    of
        false ->
            [];
        true ->
            {ok, Text} = file:read_file(
                filename:join([
                    code:priv_dir(hls_fabric),
                    "xls",
                    "templates",
                    "collection_ownership.x"
                ])
            ),
            [Text, "\n"]
    end.

-doc "Removes exclusively collector-owned messages from ordinary callback dispatch, preserving tag identities and checked collection semantics.".
-spec actor_spec(map()) -> map().
actor_spec(Spec) ->
    case
        maps:get(admission_reductions, Spec, false) == exclusive_epoch orelse
            maps:get(direct_collection, Spec, false) == exclusive_epoch
    of
        false ->
            Spec;
        true ->
            #{reductions := R = #{sites := Sites}, casts := Casts} = Spec,
            Tags = [
                maps:get(tag, C)
             || {_, C} <-
                    xls_statem_reduction_codegen:site_contributions(Sites)
            ],
            %% Keep codecs and the tag enumeration unchanged. The collector is
            %% rendered from the original artifact; only ordinary dispatch loses
            %% these clauses. A reserved tag reaching it therefore fails closed.
            Spec#{
                reductions := R#{sites := [Site#{contributions := []} || Site <- Sites]},
                casts := [C || C <- Casts, not lists:member(maps:get(tag, C), Tags)]
            }
    end.

-doc "Generates checked early folding and merges callback opens with current collection progress.".
-spec helpers(map()) -> xls_dslx:value().
helpers(Spec = #{reductions := R}) ->
    Layout = xls_machine_layout:from_spec(Spec),
    #{offset := Start, width := Width} = xls_machine_layout:field(Layout, reduction),
    #{offset := Failure} = xls_machine_layout:field(Layout, failure),
    End = Start + Width,
    {ok, Template} = file:read_file(
        filename:join([code:priv_dir(hls_fabric), "xls", "templates", "exclusive_collection.x"])
    ),
    [
        core(Spec),
        selected_input(R),
        "// Dispatch sees only an opened collection; early input remains scheduler-owned.\n",
        "fn collection_machine_bits(raw: MachineBits, reduction: ReductionState, failure: hls_failure::Code) -> MachineBits {\n  ",
        case End < xls_machine_layout:width(Layout) of
            false -> [];
            true -> ["raw[", integer_to_list(End), ":] ++ "]
        end,
        "(if reduction.status == ReductionStatus::IDLE { raw[",
        integer_to_list(Start),
        ":",
        integer_to_list(End),
        "] } else { bits_from_reduction_state(reduction) }) ++ hls_failure::first(raw[",
        integer_to_list(Failure),
        ":",
        integer_to_list(Start),
        "] as hls_failure::Code, failure) ++ raw[0:",
        integer_to_list(Failure),
        "]\n}\n\n",
        Template
    ].

%% Select the captured lift directly; its codec preserves every inactive bit too.
-spec selected_input(map()) -> iodata().
selected_input(R = #{accumulator := #{name := Name}}) ->
    #{site_bits := SiteBits, accumulator_bits := ValueBits} = xls_statem_reduction_ir:layout(R),
    Codec = xls_names:record_codec(Name),
    {ok, Template} = file:read_file(
        filename:join([
            code:priv_dir(hls_fabric),
            "xls",
            "templates",
            "collection_selected_input.x.in"
        ])
    ),
    lists:foldl(
        fun({Key, Value}, Text) -> binary:replace(Text, Key, Value, [global]) end,
        Template,
        [
            {<<"@SITE_BITS@">>, integer_to_binary(SiteBits)},
            {<<"@VALUE_BITS@">>, integer_to_binary(ValueBits)},
            {<<"@CODEC@">>, iolist_to_binary(Codec)}
        ]
    ).

-doc "Renders message-only lifting, membership checks, early folding and opening reconciliation for either execution backend.".
-spec core(map()) -> xls_dslx:value().
core(Spec = #{reductions := R, message_names := Names, message_words := Words}) ->
    #{sites := [#{population := #{size := Size}}]} = R,
    Tags = lists:usort([
        maps:get(tag, C)
     || {_, C} <-
            xls_statem_reduction_codegen:site_contributions(maps:get(sites, R))
    ]),
    {ok, Template} = file:read_file(
        filename:join([code:priv_dir(hls_fabric), "xls", "templates", "exclusive_collection_core.x"])
    ),
    [
        "// Exclusive epoch contract: contribution tags never have ordinary mailbox meaning.\n",
        "// Exactly one contribution per member; epochs cannot interleave before completion.\n",
        "// These protocol assertions are not compile-time verified.\n",
        "const COLLECTION_MEMBER_COUNT = u32:",
        integer_to_list(Size),
        ";\n\n",
        xls_reduction_codegen:transport_function(R, exclusive_epoch),
        "// Classify ownership before payload validation; malformed reserved frames fail.\n",
        "fn collection_reserved(frame: axis::Frame) -> bool {\n  ",
        lists:join(" || ", [
            ["frame.header.op == Tag::", xls_names:enum_member(T), " as u8"]
         || T <- Tags
        ]),
        "\n}\n\n",
        "// Reserved frames retain ordinary tag and packed-payload validation.\n",
        "fn collection_frame_valid(frame: axis::Frame) -> bool {\n  ",
        xls_actor_codegen:input_tag_ok(Spec, Names, Words),
        "\n}\n\n",
        "// Read the membership established by the actor's open action.\n",
        "fn collection_expected(state: ReductionState) -> ReductionMembers {\n  ",
        case xls_statem_reduction_ir:has_runtime_members(R) of
            true -> "state.expected";
            false -> ["ReductionMembers:", integer_to_list((1 bsl Size) - 1)]
        end,
        "\n}\n\n",
        Template
    ].
