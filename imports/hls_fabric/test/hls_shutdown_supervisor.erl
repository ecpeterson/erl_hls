-module(hls_shutdown_supervisor).
-moduledoc "Ordinary OTP subtree over explicitly supervised domain lifetimes; independent domain c is outside this tree.".
-behaviour(supervisor).

%% Finite fixture startup and standard supervisor declaration.
-export([start_link/2, init/1]).

-doc "Starts the ordered a,b child set with the requested ordinary OTP restart strategy.".
-spec start_link(supervisor:strategy(), [{hls_domain:domain(), pid()}]) -> supervisor:startlink_ret().
start_link(Strategy, Owners) -> supervisor:start_link(?MODULE, {Strategy, Owners}).

-doc "Delegates each domain's digital lifetime while leaving its deployment owner and external effects outside the subtree.".
-spec init({supervisor:strategy(), [{hls_domain:domain(), pid()}]}) ->
    {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Strategy, Owners}) ->
    Children = [#{id => Domain,
        start => {hls_domain_instance, start_link, [Owner, Domain, #{lifetime => supervised}]},
        restart => permanent, shutdown => 5000, type => worker} || {Domain, Owner} <- Owners],
    {ok, {#{strategy => Strategy, intensity => 10, period => 60}, Children}}.
