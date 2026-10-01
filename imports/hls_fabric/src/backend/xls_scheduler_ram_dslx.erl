%%%% xls_scheduler_ram_dslx
%%%%
%%%% Ordered DSLX channel interface shared by the scheduler and its wrappers.

-module(xls_scheduler_ram_dslx).
-moduledoc false.

-export([parameters/2, parameters/3, names/1, names/2]).
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
    [[NamePrefix, Name, ": chan<", TypePrefix, Type, "> ", Direction]
        || {Name, Type, Direction} <- channels(Access)].

-doc "Lists generated endpoints in the same order as their parameter declarations.".
-spec names(iodata()) -> [iolist()].
names(Prefix) -> names(all, Prefix).

-doc "Lists endpoints owned by the read or write half of a scheduler.".
-spec names(access(), iodata()) -> [iolist()].
names(Access, Prefix) ->
    [[Prefix, Name] || {Name, _Type, _Direction} <- channels(Access)].

%% Filter one ordered interface authority without duplicating its endpoint list.
-spec channels(access()) -> [{string(), string(), string()}].
channels(all) -> channels();
channels(Access) ->
    [Channel || Channel = {Name, _, _} <- channels(),
        string:find(Name, "_" ++ atom_to_list(Access) ++ "_") =/= nomatch].

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
