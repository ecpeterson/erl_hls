-module(xls_ir_rewrite).

-moduledoc("Shared text and audit boundaries for opt-in, single-function XLS "
           "IR rewrites. Callers supply valid optimized IR; this module is not "
           "an XLS parser or verifier.").

-export([prepare/2, index/2, node/5, write/3]).

-doc("Requires exactly one standard-format function, no procs or blocks, "
     "at least one node id, and no occurrence of the pass's reserved prefix. "
     "Returns lines and an unused id; rejects unsupported scope before "
     "any rewrite. XLS remains responsible for type and operation validity.").

-spec prepare(binary(), binary()) -> {[binary()], pos_integer()}.

prepare(Source, Prefix) ->
    {match, [_]} = re:run(Source, <<"^(?:top )?fn ">>, [multiline, global, {capture, first, binary}]),
    nomatch = re:run(Source, <<"^(?:top )?(?:proc|block) ">>, [multiline]),
    nomatch = binary:match(Source, Prefix),
    {match, Ids} = re:run(Source, <<"\\bid=([0-9]+)">>, [global, {capture, [1], binary}]),
    {binary:split(Source, <<"\n">>, [global]), 1 + lists:max([binary_to_integer(Id) || [Id] <- Ids])}.

-doc("Indexes exact line matches by their first capture, retaining other "
     "captures as binary fields. Unmatched lines are ignored; callers must "
     "establish a single valid function before indexing node names.").

-spec index([binary()], binary()) -> #{binary() => [binary()]}.

index(Lines, Pattern) ->
    lists:foldl(fun (Line, Nodes) ->
                        case re:run(Line, Pattern, [{capture, all_but_first, binary}]) of
                            {match, [Name | Fields]} -> Nodes#{Name => Fields};
                            nomatch -> Nodes
                        end
                end,
                #{},
                Lines).

-doc("Emits a bits node using an unused id and a reserved prefix checked "
     "by prepare/2. Returns its name, text, and next id. The caller owns "
     "operation/type correctness and threads the returned id through subsequent "
     "nodes.").

-spec node(binary(), pos_integer(), iodata(), iodata(), pos_integer()) -> {binary(),
                                                                           iodata(),
                                                                           pos_integer()}.

node(Prefix, Width, Op, Body, Id) ->
    Name = <<Prefix/binary, (integer_to_binary(Id))/binary>>,
    {Name,
     ["  ",
      Name,
      ": bits[",
      integer_to_list(Width),
      "] = ",
      Op,
      "(",
      Body,
      ", id=",
      integer_to_list(Id),
      ")\n"],
     Id + 1}.

-doc("Writes fresh IR and an adjacent JSON audit binding input/output bytes "
     "and changes. Existing paths and I/O failures raise; an I/O failure "
     "can leave partial outputs, which must not be treated as qualified. "
     "The audit establishes identity only, not equivalence or physical "
     "performance.").

-spec write(file:filename(), file:filename(), fun((binary()) -> {binary(), [map()]})) -> ok.

write(Input, Output, Rewrite) ->
    {error, enoent} = file:read_link_info(Output),
    {error, enoent} = file:read_link_info(Output ++ ".json"),
    {ok, Source} = file:read_file(Input),
    {Bytes, Changes} = Rewrite(Source),
    ok = file:write_file(Output, Bytes, [exclusive]),
    Audit = #{input => list_to_binary(Input), output => list_to_binary(Output),
              input_sha256 => hash(Source), output_sha256 => hash(Bytes), changes => Changes},
    ok = file:write_file(Output ++ ".json", json:encode(Audit), [exclusive]).

%% Bind evidence to bytes rather than paths or inherited experiment labels.
-spec hash(binary()) -> binary().

hash(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
