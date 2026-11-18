-module(hls_ring_dslx).
-export([write/1]).

-doc "Writes finite native-derived cursor traces for DSLX/JIT and RTL, at four capacities.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    lists:foreach(fun(N) -> write_capacity(Stage, N) end, [1, 3, 4, 7]).

%% Each vector contains a valid native ring plus one operation, including rejected operations.
-spec write_capacity(file:filename(), pos_integer()) -> ok.
write_capacity(Stage, N) ->
    T = hls_ring:ring(hls_nums:u8(), N), W = hls_type:width(T),
    {Decode, Encode} = xls_type:dslx_codec(T),
    Native = vectors(T, 900, hls_type:zero(T), rand:seed_s(exsss, {N, 23, 41}), []),
    Name = "ring" ++ integer_to_list(N),
    Source = ["#![feature(generics)]\nimport hls_ring;\nimport hls_bits;\n",
        "pub fn probe(raw: bits[", n(W), "], op: u4, value: u8) -> bits[", n(W+10), "] {\n",
        "let q = ", Decode("raw"), ";\n",
        "let (next, read, done, failed) = match op {\n", [arm(O) || O <- lists:seq(0,13)],
        "_ => { let ((done, next), failed) = hls_ring::insert_step(value, q); (next,u8:0,done,failed) },\n};\n",
        "let next = if failed { q } else { next };\nlet read = if failed { u8:0 } else { read };\n",
        "let done = done && !failed;\n(", Encode("next"), ") ++ read ++ done ++ failed\n}\n",
        "#[test]\nfn native_trace() {\nlet cases = [\n",
        [io_lib:format("(bits[~p]:~p,u4:~p,u8:~p,bits[~p]:~p),\n", [W,Raw,Op,V,W+10,Out]) || {Raw,Op,V,Out} <- Native],
        "];\nfor (entry, ()): ((bits[",n(W),"],u4,u8,bits[",n(W+10),"]), ()) in cases {\n",
        "let (raw,op,value,expected) = entry; assert_eq(probe(raw,op,value), expected);\n} (())\n}\n"],
    ok = file:write_file(filename:join(Stage, Name ++ ".x"), Source),
    ok = file:write_file(filename:join(Stage, Name ++ ".mem"), [
        io_lib:format("~*.16.0b\n", [(2*W+22+3) div 4,
            (Raw bsl (W+22)) bor (Op bsl (W+18)) bor (V bsl (W+10)) bor Out]) || {Raw,Op,V,Out} <- Native]),
    ok = file:write_file(filename:join(Stage, Name ++ ".count"), n(length(Native))).

%% Stable dispatch numbering is only the test wire protocol, not an application API.
-spec arm(non_neg_integer()) -> iodata().
arm(Op) ->
    {Name, Kind} = lists:nth(Op+1, [{rewind,queue},{at_end,flag},{next,queue},{current,value},
        {replace,queue},{full,flag},{begin_insert,queue},{empty,flag},{front,value},{pop,queue},{append,queue},{back,value},{replace_back,queue},{replace,queue}]),
    Args = case Name of F when F =:= replace; F =:= replace_back; F =:= append -> "value, q"; _ -> "q" end,
    Result = case Kind of queue -> "(result,u8:0,false,failed)"; flag -> "(q,u8:0,result,failed)";
        value -> "(q,result,false,failed)" end,
    ["u4:",n(Op)," => { let (result, failed) = hls_ring::",atom_to_list(Name),"(",Args,
        "); ",Result," },\n"].

%% A repeatable random walk records every intermediate insertion state, not just final contents.
-spec vectors(hls_type:descriptor(), non_neg_integer(), term(), rand:state(), [tuple()]) -> [tuple()].
vectors(_, 0, _, _, Acc) -> lists:reverse(Acc);
vectors(T, Left, Q, RNG, Acc) ->
    {R, RNG1} = rand:uniform_s(16, RNG), {V, RNG2} = rand:uniform_s(256, RNG1),
    Op = case R of X when X >= 15 -> 14; _ -> R-1 end,
    {Next, Read, Done, Failed} = try operation(Op, Q, V-1) of
        {A,B,C} -> {A,B,C,false}
    catch error:badarg -> {Q,0,false,true} end,
    Out = (packed(Next,T) bsl 10) bor (Read bsl 2) bor (bit(Done) bsl 1) bor bit(Failed),
    vectors(T, Left-1, Next, RNG2, [{packed(Q,T),Op,V-1,Out}|Acc]).

%% Native operations supply expected values independently of the DSLX library.
-spec operation(non_neg_integer(), term(), integer()) -> {term(), integer(), boolean()}.
operation(0,Q,_) -> {hls_ring:rewind(Q),0,false};
operation(1,Q,_) -> {Q,0,hls_ring:at_end(Q)};
operation(2,Q,_) -> {hls_ring:next(Q),0,false};
operation(3,Q,_) -> {Q,hls_ring:current(Q),false};
operation(4,Q,V) -> {hls_ring:replace(V,Q),0,false};
operation(5,Q,_) -> {Q,0,hls_ring:full(Q)};
operation(6,Q,_) -> {hls_ring:begin_insert(Q),0,false};
operation(7,Q,_) -> {Q,0,hls_ring:empty(Q)};
operation(8,Q,_) -> {Q,hls_ring:front(Q),false};
operation(9,Q,_) -> {hls_ring:pop(Q),0,false};
operation(10,Q,V) -> {hls_ring:append(V,Q),0,false};
operation(11,Q,_) -> {Q,hls_ring:back(Q),false};
operation(12,Q,V) -> {hls_ring:replace_back(V,Q),0,false};
operation(13,Q,V) -> {hls_ring:replace(V,Q),0,false};
operation(14,Q,V) -> {Done,Next}=hls_ring:insert_step(V,Q), {Next,0,Done}.

%% Serialize using the runtime codec, including physical bit order.
-spec packed(term(), hls_type:descriptor()) -> non_neg_integer().
packed(Q,T) -> Bits=hls_type:pack(Q,T), <<V:(bit_size(Bits))/little>>=Bits, V.
%% Scalar test output encoding.
-spec bit(boolean()) -> 0 | 1.
bit(false) -> 0;
bit(true) -> 1.
%% Decimal literals in generated tests.
-spec n(integer()) -> string().
n(V) -> integer_to_list(V).
