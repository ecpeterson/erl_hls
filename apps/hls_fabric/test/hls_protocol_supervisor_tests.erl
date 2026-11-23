-module(hls_protocol_supervisor_tests).
-moduledoc "Admission checks for static supervisor declarations; no hardware or OTP process is started by these tests.".
-include_lib("eunit/include/eunit.hrl").
-export([init/1]).

-doc "Supplies an ordinary OTP declaration to the composer without running children.".
-spec init({supervisor:sup_flags(),[supervisor:child_spec()]}) -> {ok,{supervisor:sup_flags(),[supervisor:child_spec()]}}.
init(Spec) -> {ok,Spec}.

%% Source order remains startup order even when the binding map sorts differently.
-spec checked_order_test() -> ok.
checked_order_test() ->
    P=hls_protocol_supervisor:plan(config(#{strategy=>one_for_one,intensity=>2,period=>5},[b,a])),
    ?assertEqual([b,a],[Id || {Id,_} <- maps:get(children,P)]),
    ?assertEqual(2,maps:get(intensity,P)).

%% Unsupported behaviors fail at elaboration rather than becoming different hardware policies.
-spec rejected_policy_test_() -> [term()].
rejected_policy_test_() ->
    [{atom_to_list(Key),?_assertError({supervisor_declaration,Reason},
        hls_protocol_supervisor:plan(config(#{Key=>Value},[a,b])))} ||
        {Key,Value,Reason} <- [{strategy,one_for_all,strategy},{intensity,17,intensity},
            {intensity,-1,intensity},{period,0,period},{auto_shutdown,all_significant,auto_shutdown},
            {unsupported,true,supervisor_flags}]].

%% Unsupported restart modes and non-domain starts reject before source generation.
-spec rejected_child_test_() -> [term()].
rejected_child_test_() ->
    [?_assertError({supervisor_declaration,Reason},hls_protocol_supervisor:plan(with_specs([Spec]))) ||
        {Spec,Reason} <- [{(child(a))#{restart=>transient},restart},
            {(child(a))#{start=>{hls_domain_instance,start_link,[symbolic_owner,a]}},child_start},
            {(child(a))#{shutdown=>brutal_kill},brutal_kill},
            {(child(a))#{type=>supervisor},child_type},
            {(child(a))#{significant=>true},significant_child}]].

%% Missing/extra/duplicate hardware bindings cannot silently change the child set.
-spec rejected_bindings_test() -> ok.
rejected_bindings_test() ->
    ?assertError({supervisor_declaration,duplicate_child},hls_protocol_supervisor:plan(config(#{},[a,a]))),
    C=config(#{},[a,b]),
    ?assertError({supervisor_declaration,child_bindings},hls_protocol_supervisor:plan(C#{children=>#{a=>#{}}})),
    ?assertError({supervisor_declaration,clock_hz},hls_protocol_supervisor:plan(C#{clock_hz=>0})).

%% The compiler consumes policy declarations; no source network is needed to check them.
-spec config(map(),[atom()]) -> hls_protocol_supervisor:config().
config(Flags,Ids) -> #{supervisor=>{?MODULE,{Flags,[child(Id) || Id <- Ids]}},
    children=>maps:from_list([{Id,#{}} || Id <- Ids]),clock_hz=>1000}.

%% Bad child declarations still use an otherwise matching hardware binding.
-spec with_specs([supervisor:child_spec()]) -> hls_protocol_supervisor:config().
with_specs(Specs) -> #{supervisor=>{?MODULE,{#{},Specs}},children=>#{a=>#{}},clock_hz=>1000}.

%% Host and FPGA forms share the same permanent domain-child declaration.
-spec child(atom()) -> supervisor:child_spec().
child(Id) -> #{id=>Id,start=>{hls_domain_instance,start_link,[symbolic_owner,Id,#{lifetime=>supervised}]},
    restart=>permanent,type=>worker,shutdown=>5000}.

%% Observation and command fields may share meaning, but never a physical pin name.
-spec duplicate_control_port_test() -> ok.
duplicate_control_port_test() ->
    ?assertError({duplicate_supervisor_ports,["child_0_target"]},
        sv_domain_supervisor:emit([], [{"reset",1},{"child_0_target",64}], [{"child_0_target",64}])).

%% Initial temporary children preserve OTP startup; compiled templates reserve dormant slots.
-spec temporary_templates_test() -> ok.
temporary_templates_test() ->
    Initial = (child(a))#{restart => temporary},
    Template = (child(b))#{restart => temporary},
    Config = (with_specs([Initial]))#{templates => [Template], children => #{a => #{}, b => #{}}},
    Plan = hls_protocol_supervisor:plan(Config),
    ?assertEqual([a,b], [Id || {Id,_} <- maps:get(children, Plan)]),
    ?assertEqual(1, maps:get(initial, Plan)),
    ?assertEqual(#{a => temporary,b => temporary}, maps:get(policies, Plan)),
    Empty = hls_protocol_supervisor:plan(Config#{supervisor => {?MODULE,{#{},[]}},
        templates => [Initial,Template]}),
    ?assertEqual(0, maps:get(initial, Empty)).

%% Dormant slots cannot introduce hidden permanent children or duplicate an initial binding.
-spec rejected_templates_test() -> ok.
rejected_templates_test() ->
    Config = config(#{},[a]),
    ?assertError({supervisor_declaration,template_policy}, hls_protocol_supervisor:plan(
        Config#{templates => [child(b)],children => #{a => #{},b => #{}}})),
    ?assertError({supervisor_declaration,duplicate_child}, hls_protocol_supervisor:plan(
        Config#{templates => [(child(a))#{restart => temporary}]})),
    ?assertError({supervisor_declaration,templates}, hls_protocol_supervisor:plan(
        Config#{templates => invalid})),
    ?assertError({supervisor_declaration,child_bindings}, hls_protocol_supervisor:plan(
        Config#{templates => [(child(b))#{restart => temporary}]})).

%% Raw composition requires explicit deployment evidence instead of inventing retirement.
-spec raw_reuse_evidence_port_test() -> ok.
raw_reuse_evidence_port_test() ->
    Inputs = [{"reset",1},{"child_0_observed_reusable",1}],
    {Public,[]} = sv_domain_supervisor:ports([],Inputs,[]),
    ?assertEqual(Inputs,Public),
    Text = iolist_to_binary(sv_domain_supervisor:emit([],Inputs,[])),
    ?assertNotEqual(nomatch,binary:match(Text,<<".child_0_observed_reusable(child_0_observed_reusable)">>)).


%% Unsupported observation must fail before child source work, not disappear from a wrapper.
-spec supervised_inspection_rejected_test() -> ok.
supervised_inspection_rejected_test() ->
    Config = (config(#{}, [a]))#{children := #{a => #{inspection => process}}},
    lists:foreach(fun(Emit) ->
        ?assertException(error, {hls_diagnostic, #{stage := supervisor,
            code := supervised_inspection_unavailable}}, Emit(Config))
    end, [fun hls_protocol_supervisor:emit/1, fun hls_protocol_supervisor:emit_stream/1]),
    ?assertException(error, {hls_diagnostic, #{stage := domain,
        code := supervised_inspection_unavailable}},
        hls_domain_stream:emit_supervised(#{network => #{inspection => #{}}})).
