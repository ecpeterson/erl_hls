-module(xls_names).
-moduledoc false.

-export([record_type/1, record_codec/1, enum_member/1,
    actor/2, reduction/3, wire_tags/1, keyword/1, import_alias/1]).

%% Keep the established artifact spelling (only the first underscore is
%% removed). Codec declarations and every caller must use the same stem.
-doc "Returns the shared DSLX struct spelling for a source record.".
-spec record_type(atom()) -> string().
record_type(Name) -> string:titlecase(lists:delete($_, atom_to_list(Name))).

-doc "Returns the shared codec stem for a source record.".
-spec record_codec(atom()) -> string().
record_codec(Name) -> string:lowercase(record_type(Name)).

-doc "Returns the DSLX spelling of a source atom used as an enum member.".
-spec enum_member(atom()) -> string().
enum_member(Name) -> string:uppercase(atom_to_list(Name)).

%% Wire identity is an Erlang contract too. DSLX spelling restrictions apply
%% only to hardware translation; they do not restrict CPU-only record names.
-doc "Rejects duplicate or reserved wire tags, independently of DSLX identifier spelling.".
-spec wire_tags([hls_source:form()]) -> ok.
wire_tags(Forms) ->
    Data = xls_parse:state(Forms),
    Tags = xls_parse:find_tags(Forms),
    _ = lists:foldl(fun(Name, Seen) ->
        Origin = record_origin(Forms, Name),
        claim(wire_tag, Name, Origin, Seen)
    end, #{none => generated(none), error => generated(error)}, [Data | Tags]),
    ok.

-doc "Checks an actor's declarations for reserved names, namespace exhaustion and generated-name collisions.".
-spec actor([hls_source:form()], hls_gs | hls_statem) -> ok.
actor(Forms, Kind) ->
    ok = control_names(Forms, Kind),
    ok = wire_tags(Forms),
    Names = [xls_parse:state(Forms) | xls_parse:find_tags(Forms)],
    SymbolKind = case {Kind, xls_parse:find_optional_attribute(Forms, hls_pending_calls)} of
        {hls_gs, {ok, _}} -> hls_gs_deferred;
        _ -> Kind
    end,
    ok = records(Forms, Names, SymbolKind),
    tags(Forms, Names).

control_names(Forms, Kind) ->
    case Kind of
        hls_gs -> ok;
        hls_statem ->
            Phases = xls_parse:find_attribute(Forms, hls_phases),
            Outputs = xls_parse:find_attribute(Forms, hls_outputs),
            ok = count(phase, Phases, 256),
            ok = count(output, Outputs, 255),
            lists:foreach(fun(Phase) ->
                case lists:member(Phase, [repeat_phase, reduce, terminate,
                        consume, postpone, fail, true, false]) of
                    true -> error({reserved_hls_statem_phase, Phase});
                    false -> ok
                end
            end, Phases),
            ok = enum(phase, declared(Forms, hls_phases, phase), #{}),
            Ports = declared(Forms, hls_outputs, output),
            ok = enum(output, Ports, #{}),
            port_channels(Ports)
    end.

port_channels(Ports) ->
    %% Top creates these channels before the per-output frame channels. A
    %% port named req would rebind req_p/req_c, changing the service wiring.
    Fixed = ["req_p", "req_c", "admit_p", "admit_c", "egress_p", "egress_c"],
    _ = lists:foldl(fun({Name, Origin}, Seen) ->
        lists:foldl(fun(Suffix, Acc) ->
            claim({proc, 'Top'}, atom_to_list(Name) ++ Suffix, Origin, Acc)
        end, Seen, ["_p", "_c"])
    end, maps:from_list([{Name, generated(Name)} || Name <- Fixed]), Ports),
    ok.

%% A private accumulator adds both a record and a wire tag. Validate it at
%% source analysis, including interface inference, before closing expressions.
-doc "Checks the private accumulator and reducer names against the actor's generated namespaces.".
-spec reduction([hls_source:form()], atom(), [map()]) -> ok.
reduction(Forms, Accumulator, Opens) ->
    Public = xls_parse:find_tags(Forms),
    case length(Public) =< 252 of
        true -> ok;
        false -> error({too_many_hls_tags_for_reduction, length(Public), 252})
    end,
    Names = [xls_parse:state(Forms) | Public] ++ [Accumulator],
    ok = records(Forms, Names, hls_statem),
    ok = tags(Forms, Names),
    %% The same reducer can be opened by several phases; only distinct
    %% Erlang names occupy distinct enum members.
    Reducers = [{Name, origin(reduction, Name, Line,
        erl_anno:file(Line))} || #{name := Name, line := Line} <- Opens],
    Unique = maps:to_list(maps:from_list(Reducers)),
    ok = count(reduction, Unique, 256),
    enum(reduction, Unique, #{}).

count(Kind, Values, Limit) ->
    case length(Values) =< Limit of
        true -> ok;
        false -> error({xls_namespace_exhausted, Kind, length(Values), Limit})
    end.

%% Imports occupy the same module namespace as types and codec functions.
-spec records([hls_source:form()], [atom()], hls_gs | hls_gs_deferred | hls_statem) -> ok.
records(Forms, Names, Kind) ->
    Fixed = maps:from_list([{Name, generated(Name)} || Name <- runtime(Kind)]),
    Runtime = lists:foldl(fun(Module, Seen) ->
        claim(module, import_alias(Module), #{kind => import, name => Module}, Seen)
    end, Fixed, xls_dslx_imports:from_forms(Forms)),
    _ = lists:foldl(fun(Name, Seen) ->
        Origin = record_origin(Forms, Name),
        Type = record_type(Name),
        Codec = record_codec(Name),
        Symbols = [{Type, record_type}, {Codec ++ "_from_bits", record_unpacker},
            {"bits_from_" ++ Codec, record_packer}],
        Next = lists:foldl(fun({Symbol, Role}, Acc) ->
            ok = identifier(module, Symbol, Origin),
            case lists:prefix("XLS_FAILURE_SITE_", Symbol) of
                true -> error({xls_name_collision, module, Symbol,
                    generated(failure_constant), Origin});
                false -> claim(module, Symbol, Origin#{kind := Role}, Acc)
            end
        end, Seen, Symbols),
        {attribute, _, record, {Name, Fields}} = xls_parse:find_record(Forms, Name),
        _ = lists:foldl(fun(Field, Acc) ->
            Bare = case Field of {typed_record_field, F, _} -> F; F -> F end,
            FieldName = xls_parse:record_field_name(Bare),
            FieldOrigin = Origin#{kind := field, name := {Name, FieldName},
                line := erl_anno:line(element(2, Bare))},
            Symbol = atom_to_list(FieldName),
            ok = identifier({field, Name}, Symbol, FieldOrigin),
            claim({field, Name}, Symbol, FieldOrigin, Acc)
        end, #{}, Fields),
        Next
    end, Runtime, Names),
    ok.

tags(Forms, Names) ->
    enum(tag, [{Name, record_origin(Forms, Name)} || Name <- Names],
        #{"NONE" => generated(none), "ERROR" => generated(error)}).

enum(Scope, Entries, Initial) ->
    _ = lists:foldl(fun({Name, Origin}, Seen) ->
        case is_atom(Name) of
            true -> ok;
            false -> error({invalid_xls_name, Scope, Name, Origin})
        end,
        %% Check before case conversion too: Unicode can uppercase to ASCII,
        %% while output channel identifiers retain the original spelling.
        ok = spelling(Scope, atom_to_list(Name), Origin),
        Symbol = enum_member(Name),
        ok = identifier(Scope, Symbol, Origin),
        claim(Scope, Symbol, Origin, Seen)
    end, Initial, Entries),
    ok.

claim(Scope, Name, Origin, Seen) ->
    case maps:find(Name, Seen) of
        {ok, Previous} -> error({xls_name_collision, Scope, Name, Previous, Origin});
        error -> Seen#{Name => Origin}
    end.

identifier(Scope, Text, Origin) ->
    ok = spelling(Scope, Text, Origin),
    case not keyword(Text) of
        true -> ok;
        false -> error({invalid_xls_identifier, Scope, Text, Origin})
    end.

spelling(Scope, Text, Origin) ->
    case re:run(Text, "^[A-Za-z_][A-Za-z0-9_]*$", [unicode, {capture, none}]) of
        match -> ok;
        nomatch -> error({invalid_xls_identifier, Scope, Text, Origin})
    end.

%% DSLX scanner_keywords.inc in the pinned XLS release. Sized keywords stop
%% at 64; arbitrary widths use uN/sN. Keep this list covered by XLS fixtures.
-doc "Reports whether a spelling is a keyword in the pinned DSLX grammar.".
-spec keyword(string()) -> boolean().
keyword([Sign | Digits] = Text) when Sign =:= $u; Sign =:= $s ->
    case string:to_integer(Digits) of
        {N, []} when N >= 1, N =< 64 -> Digits =:= integer_to_list(N);
        _ -> named_keyword(Text)
    end;
keyword(Text) -> named_keyword(Text).

%% Ordinary keywords supplement the sized integer keywords.
-spec named_keyword(string()) -> boolean().
named_keyword(Text) ->
    lists:member(Text, ["_", "as", "const", "else", "enum", "false", "fn", "for",
        "if", "impl", "import", "in", "out", "let", "match", "pub", "proc",
        "self", "struct", "trait", "true", "type", "use", "mut", "bits", "token",
        "uN", "sN", "xN", "bool", "chan", "Self"]).

record_origin(Forms, Name) ->
    [{_Form, File, Line} | _] = located(Forms, fun
        ({attribute, _, record, {N, _}}) -> N =:= Name;
        (_) -> false
    end),
    origin(record, Name, Line, File).

declared(Forms, Attribute, Kind) ->
    [{Name, origin(Kind, Name, Line, File)}
        || {{attribute, _, _, Names}, File, Line} <- located(Forms, fun
            ({attribute, _, A, _}) -> A =:= Attribute;
            (_) -> false
        end), Name <- Names].

located(Forms, Select) -> located(Forms, Select, undefined).
located([], _Select, _File) -> [];
located([{attribute, _, file, {File, _}} | Rest], Select, _) ->
    located(Rest, Select, File);
located([Form | Rest], Select, File) ->
    case Select(Form) of
        true -> [{Form, File, element(2, Form)} | located(Rest, Select, File)];
        false -> located(Rest, Select, File)
    end.

origin(Kind, Name, Line, File) ->
    #{kind => Kind, name => Name, file => File, line => erl_anno:line(Line)}.
generated(Name) -> #{kind => generated, name => Name}.

%% Reserve the actor artifact's fixed declarations in every service mode.
%% Include fixed parameters: DSLX value bindings can shadow record types.
%% N is the record codec's width parameter. Other function names cannot
%% collide with the two codec name forms or the hls_local_ helper prefix.
-spec runtime(hls_gs | hls_gs_deferred | hls_statem) -> [string()].
runtime(hls_gs_deferred) ->
    runtime(hls_gs) ++ ["STATE_BITS", "Invocation", "Outcome", "Worker", "dispatch", "reply_allowed"];
runtime(hls_gs) ->
    ["Tag", "Service", "Top", "N", "NOREPLY", "REPLY", "OK", "MAX_PAYLOAD",
        "ERROR_FUNCTION_CLAUSE", "ERROR_REQUEST_LENGTH", "ERROR_REPLY_CONTRACT", "INITIAL_STATE"];
runtime(hls_statem) ->
    ["Tag", "Phase", "Directive", "OutputPort", "Egress", "EntryEffects",
        "EntryOutcome", "ActorObservation", "MailboxSlot", "Machine", "SharedMachine", "MachineBits",
        "MachineRamReadReq", "MachineRamReadResp", "MachineRamWriteReq",
        "MachineRamWriteResp", "MailboxRamReadReq", "MailboxRamReadResp",
        "MailboxRamWriteReq", "MailboxRamWriteResp", "MachineStep", "ScheduledRequest",
        "ScheduledEffects", "SharedStep", "SharedDispatch", "SharedExecutorRequest",
        "SharedExecutorResult", "SharedPhase", "SharedState", "SharedExecutor",
        "Service", "SharedService", "EgressDemux", "Top", "ReductionStatus",
        "ReductionMode", "ReductionName", "ReductionSite", "ReductionRemaining",
        "ReductionMembers", "ReductionState", "ReductionContribution", "ReductionOutcome",
        "ReductionApply", "ReductionDispatch", "ReductionAggregate", "ReductionAggregateRequest",
        "N", "COUNT", "ACTOR_COUNT", "PRODUCER_COUNT", "STARTUP_COUNT", "INSTANCE_ID",
        "MAILBOX_CAPACITY", "MAILBOX_DEPTH", "EGRESS_DEPTH", "ENTRY_EFFECT_CAPACITY",
        "ENTRY_EFFECT_PAYLOAD_BITS", "INITIAL_MACHINE", "machine_from_bits", "bits_from_machine",
        "reduction_state_from_bits", "bits_from_reduction_state"].

-doc "Checks a qualified import and returns its local alias; reserves compiler binding prefixes.".
-spec import_alias(atom()) -> string().
import_alias(Module) ->
    Parts = string:split(atom_to_list(Module), ".", all),
    lists:foreach(fun(Part) -> identifier(import, Part, #{kind => import, name => Module}) end, Parts),
    Alias = lists:last(Parts),
    Reserved = lists:any(fun(Prefix) -> lists:prefix(Prefix, Alias) end,
        ["v_", "hls_local_", "XLS_FAILURE_SITE_"]),
    case Reserved orelse re:run(Alias, "^_[0-9]+$", [{capture, none}]) =:= match of
        true -> error({reserved_dslx_import_alias, Module, Alias});
        false -> Alias
    end.
