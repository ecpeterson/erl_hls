-module(xls_actor_debug).
-moduledoc "Binds dedicated actor observation layouts to logical topology identities and the exact xls_emitted failure codebooks. Build and debug consumers use these projections; xls_actor_observation owns the generated sampling channels, while transport and live queries are outside this module.".
%% Build and validate source-bound debug projections.
-export([projection/2, projection/3, validate/2]).
%% Compose banks and identities for external observation backends.
-export([actor_key/1, direct_bank/4, failures/1]).

%% Source metadata accepted by the canonical JSON projection encoder.
-type metadata() ::
    atom()
    | binary()
    | number()
    | [metadata()]
    | #{atom() | binary() | integer() => metadata()}.
%% Canonical JSON values after atom keys and strings have been normalized.
-type json_term() ::
    null
    | boolean()
    | binary()
    | number()
    | [json_term()]
    | #{binary() => json_term()}.

-doc "Builds a committed-state projection for dedicated actors and the exact generated artifacts.".
-spec projection(hls_topology:plan(), #{module() => xls_emitted:artifact()}) -> map().
projection(Plan, Artifacts) -> projection(Plan, Artifacts, #{direct_actor_debug => true}).
-doc "Builds the enabled dedicated actor projections; binds failure codes to generated artifacts.".
-spec projection(hls_topology:plan(), #{module() => xls_emitted:artifact()}, map()) -> map().
projection(Plan, Artifacts, Options) ->
    build(Plan, Options, fun(Module, Locations) ->
        xls_emitted:sites(maps:get(Module, Artifacts), Locations)
    end).
-doc "Checks actor identities, state layouts and source-bound failure codes against a projection.".
-spec validate(hls_topology:plan(), map()) -> ok.
validate(Plan, Projection = #{<<"banks">> := [], <<"direct">> := Banks}) ->
    ByModule = maps:from_list([{M, Fs} || #{<<"module">> := M, <<"failures">> := Fs} <- Banks]),
    Expected = build(Plan, #{direct_actor_debug => true}, fun(Module, Locations) ->
        try
            xls_failure_sites:from_catalog(
                Locations, maps:get(atom_to_binary(Module), ByModule, #{})
            )
        catch
            error:_ -> error(actor_projection_mismatch)
        end
    end),
    case Projection =:= Expected of
        true -> ok;
        false -> error(actor_projection_mismatch)
    end;
validate(_, _) ->
    error(actor_projection_mismatch).

%% Derive state observations independently of any physical sharing policy.
-spec build(hls_topology:plan(), map(), fun(
    (module(), [xls_failure_sites:location()]) -> [xls_failure_sites:site()]
)) -> map().
build(Plan, Options, Codebook) ->
    Direct =
        case xls_actor_observation:enabled(Options) of
            true -> xls_actor_observation:bindings(Plan, #{});
            false -> []
        end,
    Interfaces = hls_actor_interface:from_modules(lists:usort([M || #{module := M} <- Direct])),
    Codebooks = maps:map(
        fun(Module, #{failure_locations := Locations}) -> Codebook(Module, Locations) end,
        Interfaces
    ),
    json_value(#{
        schema => 4,
        binding => digest({Plan, direct}),
        banks => [],
        direct => [
            direct_bank(Index, Binding, maps:get(Module, Interfaces), maps:get(Module, Codebooks))
         || {Index, Binding = #{module := Module}} <- lists:enumerate(0, Direct)
        ]
    }).

-doc "Builds one actor's register observation schema and failure catalog.".
-spec direct_bank(non_neg_integer(), map(), hls_actor_interface:summary(), [
    xls_failure_sites:site()
]) -> map().
direct_bank(
    Index,
    #{id := Id, module := Module, port := Port},
    #{phases := Phases} = Interface,
    Sites
) ->
    Reduction = xls_actor_observation:collection(Interface),
    Layout = xls_actor_observation:layout(Reduction),
    Bank = #{
        index => Index,
        slots => 1,
        port => Port,
        width => maps:get(width, Layout),
        fields => maps:get(fields, Layout),
        mailbox => (maps:get(mailbox, Layout))#{
            kind => direct,
            capacity => maps:get(mailbox_capacity, Interface)
        },
        failures => failures(Sites),
        module => atom_to_binary(Module),
        phases => [atom_to_binary(P) || P <- Phases],
        actors => [
            #{
                key => actor_key(Id),
                slot => 0,
                name => iolist_to_binary(io_lib:format("~p", [Id]))
            }
        ]
    },
    case Reduction of
        none ->
            Bank;
        #{sites := ReductionSites} ->
            Bank#{
                reduction => (maps:get(reduction, Layout))#{
                    sites => [
                        maps:with([id, phase, name, population, kind], Site)
                     || Site <- ReductionSites
                    ]
                }
            }
    end.

-doc "Indexes artifact-local failure codes by their wire representation.".
-spec failures([xls_failure_sites:site()]) -> #{binary() => map()}.
failures(Sites) ->
    maps:from_list([
        {integer_to_binary(Code), maps:remove(code, Site)}
     || Site = #{code := Code} <-
            [
                #{code => C, kind => K}
             || {C, K} <- xls_failure_sites:generic()
            ] ++ Sites
    ]).

%% Converts projection metadata into JSON-compatible values and keys.
-spec json_value(metadata()) -> json_term().
json_value(Term) -> json:decode(iolist_to_binary(json:encode(Term))).

-doc "Encodes a logical actor identity deterministically for catalog lookup.".
-spec actor_key(term()) -> binary().
actor_key(Id) -> digest(Id).

%% Fingerprints a deterministic serialization of logical identity or build metadata.
-spec digest(term()) -> binary().
digest(Term) ->
    string:lowercase(
        binary:encode_hex(
            crypto:hash(
                sha256,
                term_to_binary(Term, [deterministic])
            )
        )
    ).
