-module(hls_domain_store_tests).
-include_lib("eunit/include/eunit.hrl").

%% A duplicate claimant cannot steal a live path or release another owner's claim.
-spec duplicate_path_and_release_authority_test() -> ok.
duplicate_path_and_release_authority_test() ->
    Path = path(),
    with_owner(fun(Owner) ->
        ?assertEqual(ok, request(Owner, claim, Path)),
        ?assertEqual(ok, request(Owner, claim, Path)),
        ?assertEqual({error, owned}, hls_domain_store:claim(Path)),
        ?assertEqual({error, not_owner}, hls_domain_store:release(Path)),
        ?assertEqual(ok, request(Owner, release, Path)),
        try ?assertEqual(ok, hls_domain_store:claim(Path))
        after hls_domain_store:release(Path) end
    end).

%% Actual local death permits immediate reuse even if the registry's DOWN is queued.
-spec owner_death_releases_path_test() -> ok.
owner_death_releases_path_test() ->
    Path = path(),
    with_owner(fun(Owner) ->
        ok = request(Owner, claim, Path),
        kill(Owner),
        try ?assertEqual(ok, hls_domain_store:claim(Path))
        after hls_domain_store:release(Path) end
    end).

%% Losing the registry does not forget a path whose owning process survives.
-spec registry_restart_retains_live_owner_test() -> ok.
registry_restart_retains_live_owner_test() ->
    Path = path(),
    with_owner(fun(Owner) ->
        ok = request(Owner, claim, Path),
        Registry = whereis(hls_domain_store),
        kill(Registry),
        ?assertEqual({error, owned}, hls_domain_store:claim(Path)),
        ?assertNotEqual(Registry, whereis(hls_domain_store)),
        ?assertEqual(ok, request(Owner, claim, Path)),
        ?assertEqual({error, not_owner}, hls_domain_store:release(Path)),
        ok = request(Owner, release, Path),
        try ?assertEqual(ok, hls_domain_store:claim(Path))
        after hls_domain_store:release(Path) end
    end).

%% Recovery reconciles local process death that happened while no registry existed.
-spec registry_restart_reclaims_dead_owner_test() -> ok.
registry_restart_reclaims_dead_owner_test() ->
    Path = path(),
    with_owner(fun(Owner) ->
        ok = request(Owner, claim, Path),
        kill(whereis(hls_domain_store)),
        kill(Owner),
        try ?assertEqual(ok, hls_domain_store:claim(Path))
        after hls_domain_store:release(Path) end
    end).

%% One store's owner death does not release another store's live ownership.
-spec separate_paths_remain_independent_test() -> ok.
separate_paths_remain_independent_test() ->
    A = path(), B = path(),
    with_owner(fun(First) ->
        with_owner(fun(Second) ->
            ok = request(First, claim, A),
            ok = request(Second, claim, B),
            kill(First),
            ?assertEqual(ok, request(Second, claim, B)),
            ?assertEqual({error, owned}, hls_domain_store:claim(B)),
            try ?assertEqual(ok, hls_domain_store:claim(A))
            after hls_domain_store:release(A) end
        end)
    end).

%% The old distributed namespace cannot reserve a local store or be modified by it.
-spec global_names_do_not_control_local_claims_test() -> ok.
global_names_do_not_control_local_claims_test() ->
    Path = path(),
    Name = {hls_domain, Path},
    yes = global:register_name(Name, self()),
    try
        with_owner(fun(Owner) ->
            ?assertEqual(ok, request(Owner, claim, Path)),
            ?assertEqual(self(), global:whereis_name(Name)),
            ?assertEqual(ok, request(Owner, release, Path)),
            ?assertEqual(self(), global:whereis_name(Name))
        end)
    after global:unregister_name(Name) end.

%% A stale or invented monitor notification cannot retire a living owner.
-spec stale_down_does_not_release_owner_test() -> ok.
stale_down_does_not_release_owner_test() ->
    Path = path(),
    with_owner(fun(Owner) ->
        ok = request(Owner, claim, Path),
        whereis(hls_domain_store) ! {'DOWN', make_ref(), process, Owner, killed},
        ?assertEqual({error, owned}, hls_domain_store:claim(Path))
    end).

%% Isolate ownership in a process that also retires if the test process dies.
-spec with_owner(fun((pid()) -> Result)) -> Result.
with_owner(Fun) ->
    Parent = self(),
    Owner = spawn(fun() -> owner(monitor(process, Parent)) end),
    try Fun(Owner) after kill(Owner) end.

%% Perform claims as the represented owner rather than accepting a caller-supplied PID.
-spec owner(reference()) -> ok.
owner(ParentMonitor) ->
    receive
        {Caller, Ref, Operation, Path} ->
            Reply = case Operation of
                claim -> hls_domain_store:claim(Path);
                release -> hls_domain_store:release(Path)
            end,
            Caller ! {Ref, Reply},
            owner(ParentMonitor);
        {'DOWN', ParentMonitor, process, _Parent, _Reason} -> ok
    end.

%% A bounded test exchange with one local owner process.
-spec request(pid(), claim | release, file:filename()) -> ok | {error, atom()}.
request(Owner, Operation, Path) ->
    Ref = make_ref(),
    Owner ! {self(), Ref, Operation, Path},
    receive {Ref, Reply} -> Reply after 1000 -> error(owner_did_not_reply) end.

%% Observe actual process death, including an already-dead process, before proceeding.
-spec kill(pid()) -> ok.
kill(Pid) ->
    Monitor = monitor(process, Pid),
    exit(Pid, kill),
    receive {'DOWN', Monitor, process, Pid, _} -> ok after 1000 -> error(process_survived) end.

%% Claim tests need unique path keys, not files or durable-counter mutations.
-spec path() -> file:filename().
path() -> filename:join("/tmp", "hls-domain-claim-" ++ integer_to_list(erlang:unique_integer([positive]))).
