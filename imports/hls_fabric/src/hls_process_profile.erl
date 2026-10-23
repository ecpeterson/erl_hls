-module(hls_process_profile).
-moduledoc "Bounded, serial PID sampling through the shared inspection API. Samples describe isolated coherent observations, never continuous occupancy, transitions or causal history.".
-export([capture/3, write/2]).

-doc "Samples selected catalog identities in round order. Requires a caller-named reset-free session; this assumption cannot be established by snapshots. All targets must share one process-inspection session. Options are session (nonempty binary), reset_free=true, rounds (1..10000), timeout_ms (1..60000), interval_ms (0..60000 between queries), and budget_ms (1..600000). At most 10000 queries are admitted. Stops on the first failed query, observed non-increasing clock or exhausted host budget, retaining the failed attempt and unattempted count. Query timeouts and the total budget depend on host scheduling; they do not cancel device work. Invalid options/targets raise before I/O. Callers must start a new session after reset, clock wrap, reconnect or timeout; responses from different processes are not globally atomic.".
-spec capture(map(), [term()], map()) -> map().
capture(Catalog, Identities, Options) ->
    #{session:=Session,reset_free:=true,rounds:=Rounds,timeout_ms:=Timeout,
      interval_ms:=Interval,budget_ms:=Budget}=Options,
    true=lists:sort(maps:keys(Options))=:=lists:sort([session,reset_free,rounds,timeout_ms,interval_ms,budget_ms]),
    true=is_binary(Session) andalso byte_size(Session)>0 andalso byte_size(Session)=<256,
    true=is_integer(Rounds) andalso Rounds>0 andalso Rounds=<10000,
    true=is_integer(Timeout) andalso Timeout>0 andalso Timeout=<60000,
    true=is_integer(Interval) andalso Interval>=0 andalso Interval=<60000,
    true=is_integer(Budget) andalso Budget>0 andalso Budget=<600000,
    true=is_list(Identities) andalso Identities=/=[] andalso
         length(Identities)=:=length(lists:usort(Identities)) andalso length(Identities)*Rounds=<10000,
    Targets=[target(Catalog,I)||I<-Identities],
    [{_,Binding,_}|_]=Targets,
    true=lists:all(fun({_,B,_})->B=:=Binding end,Targets),
    {_,Hash}=Binding,
    Selected=[Description||{Description,_,_}<-Targets],
    Work=lists:append(lists:duplicate(Rounds,Targets)),
    Start=erlang:monotonic_time(millisecond),
    {Rows,Stop}=sample(Work,Options,Start,Start+Budget,0,-1,[]),
    #{schema=>1,kind=>process_samples,session=>Session,fingerprint=>Hash,
      reset_free_assumption=>true,continuous_coverage=>false,options=>Options,
      selected=>Selected,rows=>Rows,stop=>Stop,planned=>length(Work),
      unattempted=>length(Work)-length(Rows),host_elapsed_ms=>erlang:monotonic_time(millisecond)-Start}.

%% Reject non-process providers and bind display identity to the catalog resource.
-spec target(map(),term()) -> {map(),{pid(),binary()},term()}.
target(Catalog,Identity) ->
    {ok,T={actor,_,{actor_snapshot,#{client:=Client,manifest:=Manifest},Id}}}=hls_debug_catalog:actor(Catalog,Identity),
    #{<<"inspection">>:=#{<<"scope">>:=<<"process">>},<<"fingerprint">>:=Hash}=Manifest,
    {#{resource=>Id,identity=>unicode:characters_to_binary(io_lib:format("~tp",[Identity]))},{Client,Hash},T}.

%% Bound outstanding transport work to one query; never retry a timed-out transaction.
-spec sample(list(),map(),integer(),integer(),non_neg_integer(),integer(),[map()]) -> {[map()],atom()}.
sample([],_,_,_,_,_,Rows) -> {lists:reverse(Rows),complete};
sample([{Description,_,Target}|Rest],Options,Start,Deadline,Ordinal,Previous,Rows) ->
    #{timeout_ms:=Timeout,interval_ms:=Interval}=Options,
    Remaining=Deadline-erlang:monotonic_time(millisecond),
    case Remaining>0 of
      false->{lists:reverse(Rows),budget_exhausted};
      true->
        Before=erlang:monotonic_time(millisecond)-Start,
        Result=hls_debug:info(Target,[cycle,initialized,phase,enter_pending,failed,failure,reduction,gather],min(Timeout,Remaining)),
        Row=Description#{ordinal=>Ordinal,request_ms=>Before,response_ms=>erlang:monotonic_time(millisecond)-Start},
        case result(Result,Previous) of
          {ok,Cycle,Fields}->
            Next=Row#{status=>ok,cycle=>Cycle,fields=>Fields},
            case Rest of []->ok; _->timer:sleep(min(Interval,max(0,Deadline-erlang:monotonic_time(millisecond)))) end,
            sample(Rest,Options,Start,Deadline,Ordinal+1,Cycle,[Next|Rows]);
          {error,Reason}->
            Failed=Row#{status=>error,error=>unicode:characters_to_binary(io_lib:format("~tp",[Reason]))},
            {lists:reverse([Failed|Rows]),query_failed}
        end
    end.

%% A decreasing/repeated serial sample clock cannot share this assumed incarnation.
-spec result(term(),integer()) -> {ok,non_neg_integer(),map()} | {error,term()}.
result(Values,Previous) when is_list(Values) ->
    Fields=maps:from_list(Values),
    case maps:get(cycle,Fields,undefined) of
      Cycle when is_integer(Cycle),Cycle>Previous,Cycle<18446744073709551616 ->
        {ok,Cycle,maps:remove(cycle,Fields)};
      Cycle->{error,{non_increasing_or_invalid_clock,Previous,Cycle}}
    end;
result(Error,_) -> {error,Error}.

-doc "Writes a capture as JSON without replacing an existing file. Erlang tuples in observation fields retain an explicit $tuple tag; no field is dropped or converted to executable text. Returns file errors, or raises for an unsupported observation value.".
-spec write(file:filename(),map()) -> ok | {error,term()}.
write(Path,Capture)->file:write_file(Path,json:encode(json_value(Capture)),[exclusive]).

%% The shared decoder exposes collection-domain tuples; preserve their shape in JSON.
-spec json_value(term()) -> term().
json_value(Value) when is_map(Value)->maps:map(fun(_,V)->json_value(V) end,Value);
json_value(Value) when is_list(Value)->[json_value(V)||V<-Value];
json_value(Value) when is_tuple(Value)->#{<<"$tuple">>=>[json_value(V)||V<-tuple_to_list(Value)]};
json_value(Value) when is_binary(Value);is_atom(Value);is_integer(Value);is_float(Value)->Value.
