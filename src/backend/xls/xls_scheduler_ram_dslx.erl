%%%% xls_scheduler_ram_dslx
%%%%
%%%% Ordered DSLX channel interface shared by the scheduler and its wrappers.

-module(xls_scheduler_ram_dslx).
-moduledoc false.

-export([parameters/2, names/1]).

%% Prefixes include their separators: [] for the actor's local declarations,
%% or e.g. "scheduler_0_" and "phi_halo_cell::" for an imported instance.
-spec parameters(iodata(), iodata()) -> [iolist()].
parameters(NamePrefix, TypePrefix) ->
    [[NamePrefix, Name, ": chan<", TypePrefix, Type, "> ", Direction]
        || {Name, Type, Direction} <- channels()].

-spec names(iodata()) -> [iolist()].
names(Prefix) ->
    [[Prefix, Name] || {Name, _Type, _Direction} <- channels()].

%% Positional config/spawn order: machine read/write, then mailbox read/write;
%% each request is immediately followed by its response (including writes).
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
