# `parse`

We (partially) recreate `regsvc` from the previous example as an Erlang `gen_server`, transpile it to XLS, and design the Erlang-side client to be retargetable between the two execution environments.

This directory is a frozen historical snapshot. Its old `xls_*` project API
names are preserved as recorded; the corresponding live APIs now use `hls_*`.

## Structure

`xls_gs` is a thin-ish wrapper over `gen_server` (GS for Gen Server).  Beyond the requirements spelled out in the behavior, modules which implement `xls_gs` are expected to meet the following requirements:

+ Provide the attribute `xls_tags` which carries a list of all the record types used to communicate between client and server.
+ `handle_call` and `handle_cast` clauses should each match on one of these declared record types, without repetition.
+ These record types should have typed fields tagged with XLS-compatible types.
+ `init/1` should carry a type specification declaring it to emit a record.

There are also some temporary requirements to simplify the example that we hope to alleviate in the future.  You'll know them when the transpiler breaks.

`xls_parse` provides two source-to-source transformations:
+ `to_xls/1` parses a module which implements the `xls_gs` behavior and translates the server components to an XLS description.  Here's how you regenerate the demo XLS: `file:write_file("regsvc.erl.x", xls_parse:to_xls("regsvc.erl"))`.
+ A parse transformation, applied with the attribute `-compile({parse_transform, xls_parse}).`, which autogenerates binary un/packing routines so that the record types reported in `xls_tags` can be de/serialized for PS<->PL comms.  This isn't necessary to run the module in PS-only mode.

`xls_type` describes a behavior used to convert between Erlang and XLS types (see, e.g., `xls_lists`, which wraps the Erlang `lists` module and maps it to XLS arrays).  This is a bit underbaked, but the basic idea is that the module provides `new`, `as`, `transpile`, `pack`, and `unpack` which are responsible for translating calls into this module to XLS; providing hooks for the explicit type mechanisms needed in XLS which Erlang elides; and providing mechanisms for de/serializing instances of these types between Erlang and XLS.

## Demo

I haven't implemented `bulk_get`, but `ping`, `set`, and `get` all work as in the previous example.

```erl
1> {ok, PID} = xls_gs:start_link(regsvc, [], [pl]).  % run on PL
{ok,<0.87.0>}
2> regsvc:ping(PID, 1234).
1234
3> regsvc:set(PID, 0, 2, 2).
4> regsvc:get(PID, 0).
2
5> regsvc:set(PID, 0, 1, 1).
6> regsvc:get(PID, 0).
3

7> {ok, PID2} = xls_gs:start_link(regsvc, []).  % run on PS
{ok,<0.95.0>}
8> regsvc:ping(PID2, 1234).
1234
9> regsvc:set(PID2, 0, 2, 2).
10> regsvc:get(PID2, 0).
2
11> regsvc:set(PID2, 0, 1, 1).
12> regsvc:get(PID2, 0).
3
```
