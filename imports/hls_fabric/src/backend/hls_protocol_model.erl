-module(hls_protocol_model).
-moduledoc "Optional application-owned wait models, checked against one fresh inventory before hardware emission. Model generation and source refinement are separate trust boundaries.".
-export([check/2, emit/1, write/2]).
-export_type([request/0, graph/0, report/0]).

-doc "No analysis, or a trusted application provider and its options. The provider must already be available on the build VM's code path; no implicit application selection or source loading occurs.".
-type request() :: none | {module(), term()}.

-doc "A proposed finite wait graph, with application-specific annotations in additional fields. Nodes and edges follow hls_protocol_wait_graph:check/2; annotations cannot grant source refinement or hardware admission.".
-type graph() :: #{nodes := [term()], edges := [map()], atom() => term()}.

-doc "Checked graph, its fresh inventory fingerprint, provider summary and separate checker result. Treat this trusted in-process build result as read-only; ETF persistence is for inspection, not admission.".
-type report() :: #{provider := module(), inventory_sha256 := binary(),
    model := graph(), application := map(), analysis := map()}.

-doc "Builds the proposed graph from the complete fresh inventory and application options. Reject unsupported source roles, phases or schemas here; never omit a dependency merely to obtain an acyclic graph. This callback may fail the build and must not emit hardware.".
-callback derive(hls_protocol_inventory:report(), term()) -> graph().

-doc "Returns a JSON-encodable application summary of the proposed model. The framework keeps it separate from the checker result; it is not a certificate. Called once during preparation, never during emission.".
-callback summary(graph()) -> map().

-doc "Invokes the selected provider once, checks its finite graph and binds the result to Inventory. Reports malformed selections or rejected graphs as diagnostics before emission; provider exceptions and malformed callback results propagate unchanged. none leaves the source build unannotated. The graph check establishes no source refinement, startup marking, fairness or program admission.".
-spec check(request(), hls_protocol_inventory:report()) -> none | report().
check(none, _) -> none;
check({Provider, Options}, Inventory) when is_atom(Provider) ->
    Model = #{nodes := Nodes, edges := Edges} = Provider:derive(Inventory, Options),
    Analysis = case hls_protocol_wait_graph:check(Nodes, Edges) of
        {ok, Checked} -> maps:remove(edges, Checked);
        {error, Why} -> hls_diagnostic:raise(model, invalid_wait_graph,
            <<"The provider's finite wait graph violates the protocol dependency contract.">>,
            #{provider => Provider, reason => Why})
    end,
    Summary = Provider:summary(Model),
    %% Force report encoding here so callback/summary failures cannot leave emitted hardware.
    _ = json:encode(Summary),
    #{provider => Provider, model => Model, application => Summary, analysis => Analysis,
      inventory_sha256 => binary:encode_hex(crypto:hash(sha256,
          term_to_binary(Inventory, [deterministic])), lowercase)};
check(Other, _) -> hls_diagnostic:raise(model, unsupported_protocol_model,
    <<"Select none or a {provider_module, options} pair for protocol-model analysis.">>, #{value => Other}).

-doc "Writes the complete trusted-local report as ETF and a compact JSON summary in an existing directory. Uses only the prepared report; it never calls the provider again. none writes nothing. Partial I/O failures are retained.".
-spec write(none | report(), file:filename()) -> ok.
write(Report, Output) ->
    hls_generated_files:write_into(#{files => emit(Report), result => ok}, Output).

-doc "Returns complete ETF and compact JSON report files from the already checked report. Does not call the provider or write files; none returns an empty file set.".
-spec emit(none | report()) -> hls_generated_files:files().
emit(none) -> #{};
emit(Report = #{provider := Provider, inventory_sha256 := Identity, application := Application,
        model := #{nodes := Nodes, edges := Edges}, analysis := Analysis}) ->
    Summary = #{provider => Provider, inventory_sha256 => Identity, application => Application,
        analysis => (maps:remove(ranks, Analysis))#{evidence => finite_graph_check,
            nodes => length(Nodes), edges => length(Edges),
            same_generation_edges => length([E || E = #{lag := 0} <- Edges]),
            older_generation_edges => length([E || E = #{lag := 1} <- Edges]),
            whole_protocol_eligible => false,
            trust_boundary => [source_extraction, application_model_provider, graph_checker]}},
    #{"protocol-model.etf" => term_to_binary(Report, [deterministic]),
      "protocol-model.json" => json:encode(Summary)}.
