-module(hls_protocol_mixed_admission_actor).
-moduledoc "Finite BEAM-only admission fixture using the actual hls_statem scheduler. The delayed callback exercises ambiguous timeout; it is not synthesizable source.".
-behaviour(hls_statem).
-export([init/1, waiting/3, running/3]).

-doc "Starts with no consumed messages; the bounded mailbox belongs to hls_statem.".
-spec init([]) -> {ok,waiting,[integer()]}.
init([])->{ok,waiting,[]}.

-doc "Postpones data until go changes phase. Slow is finite host work used to force an admission-barrier timeout after the cast arrived.".
-spec waiting(enter,atom(),[integer()]) -> {[integer()],[]};
    (cast,tuple(),[integer()]) -> {waiting|running,[integer()],consume|postpone}.
waiting(enter,_,Data)->{Data,[]};
waiting(cast,{later,_},Data)->{waiting,Data,postpone};
waiting(cast,{go},Data)->{running,Data,consume};
waiting(cast,{slow,N},Data)->timer:sleep(100),{waiting,[N|Data],consume}.

-doc "Consumes postponed and subsequent values in logical arrival order, with the newest recorded first for simple inspection.".
-spec running(enter,atom(),[integer()]) -> {[integer()],[]};
    (cast,tuple(),[integer()]) -> {running,[integer()],consume}.
running(enter,_,Data)->{Data,[]};
running(cast,{later,N},Data)->{running,[N|Data],consume}.
