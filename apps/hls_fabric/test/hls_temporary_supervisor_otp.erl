-module(hls_temporary_supervisor_otp).
-moduledoc "Ordinary initially empty OTP supervisor and finite compiled templates for the temporary-child witness.".
-behaviour(supervisor).
-export([start_link/0, init/1, templates/1, spec/2]).

-doc "Starts no children; the witness explicitly adds one of the two declared templates.".
-spec start_link() -> supervisor:startlink_ret().
start_link() -> supervisor:start_link(?MODULE, []).
-doc "Leaves admission to supervisor:start_child/2 rather than redefining temporary as dormant.".
-spec init([]) -> {ok, {supervisor:sup_flags(), []}}.
init([]) -> {ok, {#{strategy => one_for_one, intensity => 8, period => 60}, []}}.
-doc "Reserves two source-identical slots; these templates are not initial OTP child specifications.".
-spec templates(pid() | atom()) -> [supervisor:child_spec()].
templates(Owner) -> [spec(Owner, Id) || Id <- [a, b]].
-doc "Returns a fixed temporary domain child; native OTP deletes this specification when its occupant exits.".
-spec spec(pid() | atom(), a | b) -> supervisor:child_spec().
spec(Owner, Id) ->
    #{
        id => Id,
        start => {hls_domain_instance, start_link, [Owner, Id, #{lifetime => supervised}]},
        restart => temporary,
        shutdown => 5000,
        type => worker
    }.
