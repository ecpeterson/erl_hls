%%%% xls_scheduler_ram_dslx
%%%%
%%%% Ordered DSLX channel interface shared by the scheduler and its wrappers.

-module(xls_scheduler_ram_dslx).
-moduledoc "Renders the ordered DSLX endpoint signatures for scheduler state, mailbox and optional gather RAM. Actor codegen, topology wiring and the SystemVerilog RAM adapter share these names and parameter types; storage sizing belongs to retained RAM bindings.".

%% RAM channel parameter declarations.
-export([parameters/2, parameters/3, parameters/4]).

%% Matching ordered endpoint names.
-export([names/1, names/2, names/3]).
%% Each physical port belongs to exactly one side of the scheduler.
-type access() :: all | read | write.

%% Prefixes include their separators: [] for the actor's local declarations,
%% or e.g. "scheduler_0_" and "phi_halo_cell::" for an imported instance.
-doc "Declares state and mailbox RAM channels for each physical group.".
-spec parameters(iodata(), iodata()) -> [iolist()].
parameters(NamePrefix, TypePrefix) -> parameters(all, NamePrefix, TypePrefix).

-doc "Declares the read or write half of a scheduler RAM interface.".
-spec parameters(access(), iodata(), iodata()) -> [iolist()].
parameters(Access, NamePrefix, TypePrefix) ->
    parameters(Access, NamePrefix, TypePrefix, #{}).

-doc "Includes the member-masked gather store only for an offloaded collection group.".
-spec parameters(access(), iodata(), iodata(), map()) -> [iolist()].
parameters(Access, NamePrefix, TypePrefix, Group) ->
    [
        [NamePrefix, Name, ": chan<", TypePrefix, Type, "> ", Direction]
     || {Name, Type, Direction} <- channels(Access, Group)
    ].

-doc "Lists generated endpoints in the same order as their parameter declarations.".
-spec names(iodata()) -> [iolist()].
names(Prefix) -> names(all, Prefix).

-doc "Lists endpoints owned by the read or write half of a scheduler.".
-spec names(access(), iodata()) -> [iolist()].
names(Access, Prefix) ->
    names(Access, Prefix, #{}).

-doc "Lists optional gather endpoints in the same order as their declarations.".
-spec names(access(), iodata(), map()) -> [iolist()].
names(Access, Prefix, Group) ->
    [[Prefix, Name] || {Name, _Type, _Direction} <- channels(Access, Group)].

%% Filter a common ordered interface after adding its selected physical stores.
-spec channels(access(), map()) -> [{string(), string(), string()}].
channels(Access, Group) ->
    All =
        channels() ++
            case maps:get(gather_collection, Group, false) of
                false ->
                    [];
                true ->
                    [
                        {"gather_read_req_out", "GatherRamReadReq", "out"},
                        {"gather_read_resp_in", "GatherRamReadResp", "in"},
                        {"gather_write_req_out", "GatherRamWriteReq", "out"},
                        {"gather_write_resp_in", "GatherRamWriteResp", "in"}
                    ]
            end,
    case Access of
        all ->
            All;
        _ ->
            [
                Channel
             || Channel = {Name, _, _} <- All,
                string:find(Name, "_" ++ atom_to_list(Access) ++ "_") =/= nomatch
            ]
    end.

%% Positional config/spawn order: machine read/write, then mailbox read/write;
%% each request is immediately followed by its response (including writes).
-spec channels() -> [{string(), string(), string()}].
channels() ->
    [
        {"ram_read_req_out", "MachineRamReadReq", "out"},
        {"ram_read_resp_in", "MachineRamReadResp", "in"},
        {"ram_write_req_out", "MachineRamWriteReq", "out"},
        {"ram_write_resp_in", "MachineRamWriteResp", "in"},
        {"mailbox_read_req_out", "MailboxRamReadReq", "out"},
        {"mailbox_read_resp_in", "MailboxRamReadResp", "in"},
        {"mailbox_write_req_out", "MailboxRamWriteReq", "out"},
        {"mailbox_write_resp_in", "MailboxRamWriteResp", "in"}
    ].
