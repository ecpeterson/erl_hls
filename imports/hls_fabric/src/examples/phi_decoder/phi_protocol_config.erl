-module(phi_protocol_config).
-moduledoc """
Application-owned source and placement configuration for periodic repetition examples. phi_protocol_cli calls repetition/2, which selects compiler-owned line actors and topology, adds Phi protocol-model annotations, and returns a config for hls_build. It does not render source or open a runtime stream.
""".
%% Application source and placement preset.
-export([repetition/2]).

-doc "Constructs an emitter kind and trusted source configuration for N=2..16 data sites. split selects two nonempty native roles; mixed keeps data actors in BEAM. Both exclude inspection. share_arithmetic supports whole N2/N3 only. Options are split, mixed, inspect and share_arithmetic; unsupported combinations fail before emission. The twelve-round model is an annotation checked against source, not a progress or QEC guarantee.".
-spec repetition(integer(), map()) -> {hls_source_build:kind(), map()}.
repetition(Width, Options) when Width >= 2, Width =< 16 ->
    [] = maps:keys(maps:without([split, mixed, inspect, share_arithmetic], Options)),
    Split = maps:get(split, Options, none),
    Mixed = flag(mixed, Options),
    Inspect = flag(inspect, Options),
    Shared = flag(share_arithmetic, Options),
    valid_placement(Width, Split, Mixed, Inspect, Shared),
    Compiler = code:lib_dir(erl_hls),
    Source = filename:join(Compiler, "src/examples/phi_decoder"),
    Includes = [{i, filename:join(Compiler, "include")}, {i, Source}],
    Modules = [
        phenom_line_data_cell, phenom_line_syndrome_cell, phi_line_cell, phi_repetition_topology
    ],
    Base = #{
        sources => [{filename:join(Source, atom_to_list(M) ++ ".erl"), Includes} || M <- Modules],
        topology => {phi_repetition_topology, topology, [Width, 16#80000000]},
        actor_limit => 3 * Width,
        protocol_model => model(),
        dslx_path => [Source]
    },
    {Kind, Placement} = placement(Width, Split, Mixed),
    Config = maps:merge(Base, Placement),
    Inspection =
        case Inspect of
            true -> Config#{inspection => process};
            false -> Config
        end,
    {Kind,
        case Shared of
            true ->
                Inspection#{arithmetic_groups => [[{phi, X, 0} || X <- lists:seq(0, Width - 1)]]};
            false ->
                Inspection
        end};
repetition(Width, _) ->
    error({repetition_width, Width}).

%% CLI values and direct callers share one boolean validation boundary.
-spec flag(atom(), map()) -> boolean().
flag(Key, Options) ->
    case maps:get(Key, Options, false) of
        Value when is_boolean(Value) -> Value;
        Value -> error({repetition_flag, Key, Value})
    end.

%% Keep unsupported placement and observation combinations explicit.
-spec valid_placement(integer(), term(), boolean(), boolean(), boolean()) -> ok.
valid_placement(Width, Split, Mixed, Inspect, Shared) ->
    case Split of
        none -> ok;
        K when is_integer(K), K > 0, K < Width, not Mixed, not Inspect -> ok;
        _ -> error({repetition_split, Split})
    end,
    case Mixed andalso Inspect of
        true -> error(repetition_mixed_inspection);
        false -> ok
    end,
    case Shared andalso (Width > 3 orelse Split =/= none orelse Mixed) of
        true -> error(repetition_shared_placement);
        false -> ok
    end.

%% Placement names and addresses belong to this example, not the compiler driver.
-spec placement(integer(), none | integer(), boolean()) -> {hls_source_build:kind(), map()}.
placement(Width, none, true) ->
    {mixed, #{
        control => rectangle,
        native_actors => actors([syndrome, phi], 0, Width - 1),
        host => 1,
        service => 7
    }};
placement(_, none, false) ->
    {application, #{device => board, host => 1}};
placement(Width, Split, false) ->
    {deployment, #{
        control => rectangle,
        devices => #{
            0 => #{
                native_actors => actors([data, syndrome, phi], 0, Split - 1),
                host => 1,
                service => 7
            },
            1 => #{
                native_actors => actors([data, syndrome, phi], Split, Width - 1),
                host => 1,
                service => 17
            }
        },
        limits => #{crossings => 8, commands => 128, events => 128}
    }}.

%% Preserve source topology IDs and the example's family-major ordering.
-spec actors([atom()], integer(), integer()) -> [tuple()].
actors(Families, First, Last) ->
    [{Family, X, 0} || Family <- Families, X <- lists:seq(First, Last)].

%% These annotations propose dependencies; the source model checker validates coverage.
-spec model() -> hls_protocol_model:request().
model() ->
    {phi_protocol_model, #{
        phenom_line_data_cell => #{
            role => data, phases => [configuring, collecting, reporting, replying]
        },
        phenom_line_syndrome_cell => #{
            role => syndrome, phases => [configuring, collecting, announcing]
        },
        phi_line_cell => #{
            role => phi,
            rounds => 12,
            phases => [configuring, measuring, gathering, comparing, flipping]
        }
    }}.
