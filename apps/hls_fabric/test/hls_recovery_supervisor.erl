-module(hls_recovery_supervisor).
-moduledoc "Ordinary OTP supervision for the explicitly reset-safe simulated recovery actuator. Its device and resource owner remain outside this subtree.".
-behaviour(supervisor).

%% Supervisor startup and OTP callback.
-export([start_link/2, init/1]).

-doc "Starts one permanent domain representative, allowing two restarts within sixty seconds.".
-spec start_link(pid(), hls_domain:domain()) -> supervisor:startlink_ret().
start_link(Owner, Domain) -> supervisor:start_link(?MODULE, {Owner, Domain}).

-doc "Replaces only the domain representative; the deployment owner and external device are not supervisor children.".
-spec init({pid(), hls_domain:domain()}) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Owner, Domain}) ->
    {ok, {#{strategy => one_for_one, intensity => 2, period => 60},
        [#{id => instance, start => {hls_domain_instance, start_link, [Owner, Domain]},
            restart => permanent, shutdown => 1000, type => worker}]}}.
