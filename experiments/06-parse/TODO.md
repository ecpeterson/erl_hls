# TODO

A partial list of things missing from this demo:

XLS does not permit functions which parametrize over struct types, functions whose parametrization branches are individually specified, or casting between struct and bits types. Accordingly, we have these `*_from_bits` and `bits_from_*` functions running around, which are kind of unseemly.
+ XLS also doesn't permit bounded sum types; the only option is to cast all the way up to bits. This + the inability to select a cast method based on the type has led us to model records in the computation as triples `(tag, struct, bits)`, of which struct is the source of truth, but from which we can extract its type (in the form of the tag) and its upcast value (the bits) even after some processing passes. So long as these usages are terminal, this isn't exactly _defeating_ the XLS type system, but it is abusive.
    + Part of the problem here is that the transpiler is a stupid AST-to-iolist transformation. We might make our lives easier overall by doing an Erlang-AST-to-XLS-AST transformation and then XLS-AST-to-iolist printer.
        + Relatedly, I was sloppy about the return types of different AST helpers, eg, whether they return an attribute or its contents (since the caller knows what the attribute is named!). There's plenty of opportunity to be more principled in pursuit debuggability.
+ I haven't fully thought through the interface in `xls_type`. Really nailing down a few of these basic data types — lists, queues — would be really helpful.
    + I also haven't fully thought through the relationship to the basic datatypes in `xls_types`, e.g., how `new` is threaded through. I also have not been chasing recursively defined types properly, since that's bound up with this same specification problem. I also skipped over these aspects of serialization — un/pack handle records gracefully and ignore all type info about their slots, indiscriminately jamming them into `32/little-unsigned-integer`s. We should probably have recursive de/ser.
+ We should also provide FFI + mocks for hardware peripherals (e.g., DSP components, or an ethernet PHY) which we _won't_ synthesize from Erlang but with which our Erlang-to-XLS processes will interact and whose behaviors we'll want to test on the Erlang side.
+ Should break apart the transpiler from the parse transform. They share a couple of tools, but they mostly don't interact.
+ I haven't thought at all about hosting multiple processes or how to fan PS<->PL comms.
    + It would be easiest to start with individually named processes, but a set of ephemeral processes which has a bounded live set may also be possible.
    + PL-PL comms and address translation sounds like an interesting problem to solve.
    + I think a comparison between the reset chain and supervision trees is super promising.
+ Many `gen_server` features are given very limited exposure in `xls_gs`.
    + A high-precedence timeout seems easy to implement with a counter.
    + Calls are obligated to respond, casts can't generate messages, no side-effects via out-of-band messages, … . Plenty to implement here.
+ I left off a bunch of safety features in the emitted code, e.g., the transpiler is set up in such a way that it should be trivial to check that shared-name results all match, else we send back an error code. (As said, though, this wouldn't be Erlang-y; I think the most reasonable default would be to reset to the init state, as if supervised with a restart.)
    + I also left off a bunch of safety features in the transpiler. It's still possible to tell what's going on since unvarnished Erlang error messages tend to report the arguments of the crashing function call, which tends to include an AST line number, but it's painful.
+ Deployment is very hand-rolled. Would be great to package as much as possible into rebar.
    + The cumbersomeness of Vivado is a significant part of why this is hand-rolled. We could spend time exploring alternative toolchains which cover the chipsets we have in test.
+ I promised to think about whether `-enum` would actually make my life meaningfully better, especially around binary unpacking. So far I think the answer is basically "no" if I'm doing nontrivial codegen anyway from `-xls_tags`, but maybe it'd be nice to get a lift from dialyzer ahead of codegen. I don't know.
