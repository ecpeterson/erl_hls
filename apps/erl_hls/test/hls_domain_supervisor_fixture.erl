-module(hls_domain_supervisor_fixture).
-moduledoc "Ordinary OTP supervisor used to witness replacement of a managed source domain.".
-behaviour(supervisor).
-export([start_link/2, init/1]).

-doc "Starts one permanent domain representative with a bounded restart intensity.".
-spec start_link(pid(), hls_domain:domain()) -> supervisor:startlink_ret().
start_link(Owner, Domain) -> supervisor:start_link(?MODULE, {Owner, Domain}).

-doc "Keeps the deployment owner outside the child's restart scope.".
-spec init({pid(), hls_domain:domain()}) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Owner, Domain}) ->
    {ok, {#{strategy => one_for_one, intensity => 4, period => 10},
        [#{id => instance, start => {hls_domain_instance, start_link, [Owner, Domain]},
            restart => permanent, shutdown => 1000, type => worker}]}}.
