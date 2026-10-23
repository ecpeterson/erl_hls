-module(hls_protocol_periodic_model).
-moduledoc "Builds a periodic wait model for explicitly annotated neighbor-barrier source contracts. The model handles one-round noise prefetch and fixed typed-slot reuse; it does not certify source refinement or program admission.".
-export([derive/2]).

-doc "Derives a finite graph from exact source routes and an explicit module-to-role annotation. Roles are data, syndrome or phi; each supplies its complete expected phase list and Phi supplies a positive rounds bound. Rejects unrecognized internal schemas or route endpoints. Every internal channel gets capture, receive and reuse dependencies, preserving duplicate labelled ports to one PID. A successful rank concerns this proposed model only: initialization, source guards/keys/batches, local arbitration, host sequencing and runtime refinement remain qualification obligations.".
-spec derive(map(), map()) -> map().
derive(#{actors := Actors, channels := Channels, modules := Modules, diagnostics := Diagnostics}, Contracts) ->
    need(Diagnostics =:= [], {source_diagnostics, Diagnostics}),
    need(lists:sort(maps:keys(Contracts)) =:= lists:sort(maps:keys(Modules)), incomplete_role_annotations),
    Ids = [Id || #{id := Id} <- Actors],
    need(Ids =/= [] andalso length(Ids) =:= length(lists:usort(Ids)), duplicate_or_empty_actor_population),
    Owners = maps:from_list([{Id, contract(Module, Modules, Contracts)} || #{id := Id, module := Module} <- Actors]),
    Internal = [C || C = #{destination := {actor, _}} <- Channels],
    Traces = maps:map(fun(Id, C) -> trace(Id, C) end, Owners),
    SourceNodes = lists:append(maps:values(Traces)),
    Local = lists:append([local_edges(Id, C) || {Id, C} <- maps:to_list(Owners)]),
    Messages = lists:append([messages(C, Owners) || C <- Internal]),
    Keys = [maps:get(capture, M) || M <- Messages],
    need(length(Keys) =:= length(lists:usort(Keys)), duplicate_periodic_channel),
    Delivery = lists:append([delivery(M, Messages) || M <- Messages]),
    Publishers = lists:append([publisher(Id, C, Messages) || {Id, C} <- maps:to_list(Owners)]),
    Order = sender_order(Messages),
    Entry = lists:append([empty_entry(Id, C, Messages) || {Id, C} <- maps:to_list(Owners)]),
    Edges = lists:usort(Local ++ Delivery ++ Publishers ++ Order ++ Entry),
    Ranked = case hls_protocol_wait_graph:check(SourceNodes ++ Keys, Edges) of
        {ok, Ranking} -> Ranking;
        {error, Why} -> error({periodic_model, Why})
    end,
    #{nodes => SourceNodes ++ Keys, edges => Edges, ranks => maps:get(ranks, Ranked),
      messages => Messages, actor_count => length(Actors), internal_channels => length(Internal),
      source_contracts => Contracts, source_refinement => unestablished,
      startup_marking => unestablished, whole_protocol_eligible => false,
      obligations => [source_phase_and_generation_invariants, source_publication_and_receipt_refinement,
          initial_configuration_and_prefetch, source_to_runtime_refinement,
          fair_selection_and_sinks, bounded_host_control_and_no_wrap],
      exclusions => [source_error_freedom, application_convergence, native_timing]}.

%% Role annotations must match the complete source phase set; names alone never qualify a role.
-spec contract(module(), map(), map()) -> map().
contract(Module, Modules, Contracts) ->
    C = #{role := Role, phases := Phases} = maps:get(Module, Contracts),
    need(lists:sort(Phases) =:= lists:sort(maps:get(phases, maps:get(Module, Modules))),
        {phase_coverage, Module}),
    case Role of
        phi ->
            R = maps:get(rounds, C, undefined),
            need(is_integer(R) andalso R > 0 andalso R =< 256, {rounds, Module, R});
        data -> ok;
        syndrome -> ok;
        _ -> error({periodic_model, {unsupported_role, Module, Role}})
    end,
    C.

%% Each node is an acquisition, publication or complete local barrier, not a physical clock.
-spec node(term(), term()) -> term().
node(Id, Stage) -> {actor, Id, Stage}.

%% Noise release(t) publishes anyon(t) and query(t+1) in the same source snapshot.
-spec stages(map()) -> [term()].
stages(#{role := data}) -> [query, report];
stages(#{role := syndrome}) -> [data, release];
stages(#{role := phi, rounds := R}) ->
    [request, anyon] ++ lists:append([[{diffusion_send, K}, {diffusion_receive, K}] || K <- lists:seq(0, R-1)]) ++
    [comparison_send, comparison_receive, movement_send, movement_receive].

%% Periodic stages exclude startup/host sequencing, which remain explicit qualification obligations.
-spec trace(term(), map()) -> [term()].
trace(Id, Contract) -> [node(Id, S) || S <- stages(Contract)].

%% Local progress is monotone within one round; the next request starts after prior movement.
-spec local_edges(term(), map()) -> [map()].
local_edges(Id, C) ->
    Ns = trace(Id, C),
    Chain = [edge(B, A, 0, dependency) || {A, B} <- lists:zip(lists:droplast(Ns), tl(Ns))],
    case C of
        #{role := phi} -> [edge(hd(Ns), lists:last(Ns), 1, generation_progress) | Chain];
        _ -> Chain
    end.

%% Every internal source channel must fit a declared role/schema relation; labels remain distinct.
-spec messages(map(), map()) -> [map()].
messages(#{source := S, destination := {actor, D}, port := Port, tag := Tag, alternatives := Alternatives}, Owners) ->
    SC = maps:get(S, Owners), DC = maps:get(D, Owners),
    ExpectedPhase = case Tag of
        phenom_query -> collecting; phenom_anyon -> collecting; phenom_data -> reporting;
        phenom_request -> measuring; phi -> gathering; phi0 -> comparing; anyon_move -> flipping;
        _ -> error({periodic_model, {unsupported_schema, Tag}})
    end,
    need([ExpectedPhase] =:= lists:usort([P || #{phase := P} <- Alternatives]),
        {publication_phase, S, Port, Tag}),
    Orders = maps:from_list([{L, O} || #{layout := L, order := O} <- Alternatives]),
    Shape = case {maps:get(role, SC), maps:get(role, DC), Tag} of
        {syndrome, data, phenom_query} -> [{0, release, query, 1}];
        {data, syndrome, phenom_data} -> [{0, report, data, 0}];
        {phi, syndrome, phenom_request} -> [{0, request, release, 0}];
        {syndrome, phi, phenom_anyon} -> [{0, release, anyon, 0}];
        {phi, phi, phi} ->
            R = maps:get(rounds, SC),
            need(R =:= maps:get(rounds, DC), {neighbor_rounds, S, D}),
            [{K, {diffusion_send, K}, {diffusion_receive, K}, 0} || K <- lists:seq(0, R-1)];
        {phi, phi, phi0} -> [{0, comparison_send, comparison_receive, 0}];
        {phi, phi, anyon_move} -> [{0, movement_send, movement_receive, 0}];
        Other -> error({periodic_model, {unsupported_channel, S, D, Port, Other}})
    end,
    [#{key => {S, D, Port, Tag}, iteration => K, capture => {capture, S, D, Port, Tag, K},
       source => S, destination => D, send => node(S, Send), receive_node => node(D, Receive),
       receive_offset => Offset, layout_orders => Orders} || {K, Send, Receive, Offset} <- Shape].

%% Query storage holds a message for the following round; reuse waits for this round's receipt.
-spec delivery(map(), [map()]) -> [map()].
delivery(#{key := Key, iteration := K, capture := Capture, send := Send,
        receive_node := Receive, receive_offset := Offset}, All) ->
    Same = [M || M = #{key := Other} <- All, Other =:= Key],
    Last = lists:max([I || #{iteration := I} <- Same]),
    Previous = case K of 0 -> Last; _ -> K-1 end,
    [#{receive_node := LastRead}] = [M || M = #{iteration := I} <- Same, I =:= Previous],
    Lag = case K of 0 -> 1-Offset; _ -> 0 end,
    Reuse = case Lag of
        0 -> edge(Capture, LastRead, 0, dependency);
        1 -> (edge(Capture, LastRead, 1, storage_reuse))#{resource => Key}
    end,
    [edge(Capture, Send, 0, dependency), edge(Receive, Capture, Offset, generation_progress), Reuse].

%% A new source snapshot waits for every internal recipient of the prior snapshot to accept it.
%% External sinks are separately required fair; conditional outputs do not imply convergence.
-spec publisher(term(), map(), [map()]) -> [map()].
publisher(Id, C, Messages) ->
    Sends = case C of
        #{role := data} -> [report];
        #{role := syndrome} -> [release];
        #{role := phi, rounds := R} -> [request] ++ [{diffusion_send, K} || K <- lists:seq(0, R-1)] ++ [comparison_send, movement_send]
    end,
    Nodes = [node(Id, S) || S <- Sends],
    Previous = [lists:last(Nodes) | lists:droplast(Nodes)],
    lists:append([[case Next =:= hd(Nodes) of
        true -> (edge(Next, Capture, 1, storage_reuse))#{resource => {publisher, Id}};
        false -> edge(Next, Capture, 0, dependency)
    end || #{source := Source, send := Send, capture := Capture} <- Messages,
        Source =:= Id, Send =:= Prev] || {Next, Prev} <- lists:zip(Nodes, Previous)]).

%% Runtime reserves publication capacity even for empty collecting entries.
%% Data/syndrome cannot accept the next round until their preceding batch drains.
-spec empty_entry(term(), map(), [map()]) -> [map()].
empty_entry(Id, #{role := Role}, Messages) when Role =:= data; Role =:= syndrome ->
    Next = case Role of data -> query; syndrome -> data end,
    [(edge(node(Id, Next), Capture, 1, storage_reuse))#{resource => {publisher, Id}}
        || #{source := Source, capture := Capture} <- Messages, Source =:= Id];
empty_entry(_, #{role := phi}, _) -> [].

%% Preserve actual per-destination source order only for channels co-occurring in a layout.
-spec sender_order([map()]) -> [map()].
sender_order(Messages) ->
    [edge(B, A, 0, sender_order) ||
        #{source := S, destination := D, send := Send, capture := A, layout_orders := LA} <- Messages,
        #{source := T, destination := E, send := Other, capture := B, layout_orders := LB} <- Messages,
        S =:= T, D =:= E, Send =:= Other, A =/= B,
        lists:any(fun({L, OA}) -> case maps:find(L, LB) of
            {ok, OB} -> OA < OB; error -> false end
        end, maps:to_list(LA))].

%% Positive lags name a separate source-generation obligation; zero-lag dependencies stay ordinary.
-spec edge(term(), term(), 0 | 1, atom()) -> map().
edge(W, P, 0, Kind) ->
    K = case Kind of sender_order -> sender_order; _ -> dependency end,
    #{waiter => W, prerequisite => P, lag => 0, kind => K};
edge(W, P, 1, Kind) -> #{waiter => W, prerequisite => P, lag => 1, kind => Kind,
    obligation => source_checked_generation_and_initial_marking}.

%% Reject an unsupported annotation instead of dropping its dependencies.
-spec need(boolean(), term()) -> ok.
need(true, _) -> ok;
need(false, Why) -> error({periodic_model, Why}).
