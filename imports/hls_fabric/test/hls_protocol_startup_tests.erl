-module(hls_protocol_startup_tests).
-include_lib("eunit/include/eunit.hrl").

%% Unaligned signed and unsigned fields retain their ordinary physical stream order.
-spec exact_frame_test() -> ok.
exact_frame_test() ->
    A=artifact([{id,type(uN,[3])},{value,type(sN,[13])},{flag,{hls_record_type,1,{hls_type,hls_bool,bool,[]}}}]),
    [F,F]=hls_protocol_startup:frames(A,[{message,5,-21,true},{message,5,-21,true}]),
    Parts=[hls_type:pack_exact(5,{hls_type,hls_nums,uN,[3]}),
           hls_type:pack_exact(-21,{hls_type,hls_nums,sN,[13]}),hls_type:pack_exact(true,{hls_type,hls_bool,bool,[]})],
    Stream = << <<B/bitstring>> || B <- Parts >>,
    <<Payload:96/little>> = <<Stream/bitstring,0:(96-bit_size(Stream))>>,
    ?assertEqual((Payload bsl 32) bor (3 bsl 24) bor 1,F).

%% Empty configuration adds no messages; empty records still have their canonical operation header.
-spec empty_test() -> ok.
empty_test() -> A=artifact([]),?assertEqual([],hls_protocol_startup:frames(A,[])),
    ?assertEqual([3 bsl 24],hls_protocol_startup:frames(A,[{message}])).

%% Record tags, arities and host representation must match the complete receiving schema.
-spec rejects_bad_records_test() -> ok.
rejects_bad_records_test() ->
    A=artifact([{n,type(u8,[])}]),
    lists:foreach(fun(M)->?assertError({invalid_startup_record,M},hls_protocol_startup:frames(A,[M])) end,
        [bad,{other,1},{message},{message,1,2}]),
    ?assertException(error,_,hls_protocol_startup:frames(A,[{message,256}])),
    ?assertException(error,_,hls_protocol_startup:frames(A,[{message,1.0}])).

%% The ordinary frame capacity is enforced before any hardware emission.
-spec rejects_wide_payload_test() -> ok.
rejects_wide_payload_test() ->
    A=artifact([{n,type(uN,[97])}]),
    ?assertException(error,_,hls_protocol_startup:frames(A,[{message,0}])).

%% Fixture ASTs exercise the same source record/type boundary used by fresh compilation.
-spec artifact([{atom(),term()}]) -> map().
artifact(Fields) -> #{spec=>#{message_names=>[message]},plan=>#{records=>[
    {attribute,1,record,{message,[{typed_record_field,{record_field,1,{atom,1,K}},T}||{K,T}<-Fields]}}]}}.

%% Use ordinary compiler type descriptors, including non-byte-aligned scalar widths.
-spec type(atom(),[integer()]) -> term().
type(Name,Args) -> {hls_record_type,1,{hls_type,hls_nums,Name,Args}}.
