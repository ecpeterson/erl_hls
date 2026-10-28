-module(xls_direct_collection_codegen).
-moduledoc "Validates and renders an asserted exclusive reduction beside a singleton actor mailbox. xls_scheduler_actor checks this optional policy before xls_scheduler_codegen installs the direct-owner DSLX body; general collection semantics remain source-owned.".

%% Singleton policy validation.
-export([validate/2]).

%% Direct-owner DSLX body.
-export([body/1]).

-doc "Requires one exclusive member reduction and excludes reply/internal-event runtimes until explicitly integrated.".
-spec validate(map(), map()) -> ok.
validate(Spec, Options) ->
    case maps:get(direct_collection, Options, false) of
        false ->
            ok;
        exclusive_epoch ->
            case
                {
                    maps:get(shared_service, Options, ordinary),
                    maps:get(admission_reductions, Options, false)
                }
            of
                {ordinary, false} -> ok;
                _ -> error(direct_collection_incompatible_shared_service)
            end,
            case
                {
                    maps:get(reductions, Spec, none),
                    xls_statem_reply_codegen:enabled(Spec),
                    maps:get(continuations, Spec, [])
                }
            of
                {R, false, []} when is_map(R) -> xls_exclusive_collection_codegen:validate(R);
                _ -> error(direct_collection_requires_reduced_statem)
            end;
        Other ->
            error({direct_collection, Other})
    end.

-doc "Adds an optional singleton receiver around the ordinary compiled actor callbacks.".
-spec body(map()) -> xls_dslx:value().
body(#{direct_collection := exclusive_epoch} = Spec) ->
    {ok, Template} = file:read_file(
        filename:join([
            code:priv_dir(hls_fabric),
            "xls",
            "templates",
            "direct_collection.x"
        ])
    ),
    [xls_exclusive_collection_codegen:core(Spec), Template, service(Spec)];
body(_) ->
    [].

%% The existing mailbox engine still owns commands, entry, completion and
%% failure. Its admission bookkeeping is local: no reserved frame acquires a
%% mailbox credit and no credit channel sits on the collector's recurrence.
-spec service(map()) -> iodata().
service(Spec) ->
    {ok, Template} = file:read_file(
        filename:join([
            code:priv_dir(hls_fabric),
            "xls",
            "templates",
            "direct_collection_service.x.in"
        ])
    ),
    xls_template:render(Template, [
        {<<"@@DEBUG_FIELD@@">>, xls_actor_observation:proc_field(Spec)},
        {<<"@@DEBUG_PARAMETER@@">>, xls_actor_observation:config_parameter(Spec)},
        {<<"@@DEBUG_VALUE@@">>, xls_actor_observation:config_value(Spec)},
        {<<"@@DEBUG_SAMPLE@@">>, xls_actor_observation:sample(Spec)}
    ]).
