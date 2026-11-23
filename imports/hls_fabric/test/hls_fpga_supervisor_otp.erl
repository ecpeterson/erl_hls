-module(hls_fpga_supervisor_otp).
-moduledoc "Ordinary OTP declaration used by the native reference and checked FPGA supervisor elaboration. The deployment owner stays outside this subtree.".
-behaviour(supervisor).

%% Native startup and the shared ordinary supervisor declaration.
-export([start_link/2, init/1]).

-doc "Starts permanent representatives for the two independently resettable source domains.".
-spec start_link(pid(), supervisor:sup_flags()) -> supervisor:startlink_ret().
start_link(Owner, Flags) -> supervisor:start_link(?MODULE, {Owner, Flags}).

-doc "Declares a,b in startup order. Elaboration may supply an owner placeholder; runtime startup supplies its actual deployment owner.".
-spec init({pid() | atom(), supervisor:sup_flags()}) ->
    {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Owner, Flags}) ->
    Children = [#{id => Domain,
        start => {hls_domain_instance, start_link, [Owner, Domain, #{lifetime => supervised}]},
        restart => permanent, shutdown => 5000, type => worker} || Domain <- [a, b]],
    {ok, {Flags, Children}}.
