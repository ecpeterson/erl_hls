-module(hls_recovery_actuator_fixture).
-moduledoc "Finite source actuator for recovery-interface witnesses; digital profiles are not claims about an external resource's validity.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-include("hls_recovery_profile.hrl").
-hls_data(cell).
-hls_phases([active]).
-hls_tags([select_profile, query_profile, apply_profile, controller_failure, profile_status, profile_applied]).
-hls_outputs([effect, reply]).
-hls_reply_port(reply).
-hls_mailbox_capacity(4).
-hls_pending_calls(1).
-hls_replies([{select_profile, [profile_status]}, {query_profile, [profile_status]}]).

%% Source callbacks; the same actor runs under the ERTS domain backend.
-export([init/1, active/3, topology/0]).

%% Only one pending/last transition is stored; the older physical profile is not a command log.
-record(cell, {
    epoch = hls_type:zero() :: hls_nums:u32(),
    profile = hls_type:zero() :: hls_nums:u8(),
    request = hls_type:zero() :: hls_nums:u32(),
    requested_epoch = hls_type:zero() :: hls_nums:u32(),
    requested_profile = hls_type:zero() :: hls_nums:u8(),
    pending = hls_type:zero() :: hls_bool:bool(),
    publish = hls_type:zero() :: hls_bool:bool()
}).

-doc "Starts with no confirmed physical configuration or pending request.".
-spec init([]) -> {ok, active, #cell{}}.
init([]) -> {ok, active, #cell{}}.

-doc "Selects one bounded profile, applies it once on a matching trigger, and reports live status; expected rejections are replies, while controller_failure terminates the incarnation.".
-spec active(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    ({call, hls_gs:from()}, #select_profile{} | #query_profile{}, #cell{}) -> hls_statem:call_result(#cell{});
    (cast, #apply_profile{} | #controller_failure{}, #cell{}) -> hls_statem:cast_result(#cell{}).
active(enter, _Old, Cell) ->
    case Cell#cell.publish of
        true ->
            Event = #profile_applied{request = Cell#cell.request, epoch = Cell#cell.epoch,
                profile = Cell#cell.profile, enabled = profile_mask(Cell#cell.profile)},
            {Cell#cell{publish = false}, [{cast, effect, Event}]};
        false -> {Cell, []}
    end;
%% Selection reserves one transition; a repeated live request retrieves the same outcome.
active({call, From}, Request = #select_profile{}, Cell) ->
    {Status, Next} = select(Request, Cell),
    {active, Next, consume, [{reply, From, report(Status, Request#select_profile.request, Next)}]};
%% Once a newer transition replaces the record, older identities have an unknown outcome here.
active({call, From}, #query_profile{request = Request, epoch = Epoch}, Cell) ->
    Status = case Request =/= 0 andalso Request =:= Cell#cell.request andalso
        Epoch =:= Cell#cell.requested_epoch of
        true -> live_status(Cell);
        false -> ?PROFILE_UNKNOWN
    end,
    {active, Cell, consume, [{reply, From, report(Status, Request, Cell)}]};
%% Both request and expected epoch must match; stale triggers cannot apply a newer reuse of the ID.
active(cast, #apply_profile{request = Request, epoch = Epoch}, Cell) ->
    case Cell#cell.pending andalso Request =:= Cell#cell.request andalso
        Epoch =:= Cell#cell.requested_epoch of
        true ->
            Next = Cell#cell{epoch = Cell#cell.epoch + 1, profile = Cell#cell.requested_profile,
                pending = false, publish = true},
            {repeat_phase, Next, consume};
        false -> {active, Cell, consume}
    end;
%% Fault retirement does not reverse any effect already sent to the external endpoint.
active(cast, #controller_failure{}, Cell) -> {active, Cell, fail}.

%% Return a normal rejection without modifying admission, configuration or the existing request.
-spec select(#select_profile{}, #cell{}) -> {hls_nums:u8(), #cell{}}.
select(Request, Cell) ->
    Same = Request#select_profile.request =/= 0 andalso
        Request#select_profile.request =:= Cell#cell.request andalso
        Request#select_profile.epoch =:= Cell#cell.requested_epoch andalso
        Request#select_profile.profile =:= Cell#cell.requested_profile,
    case Same of
        true -> {live_status(Cell), Cell};
        false ->
            case Request#select_profile.request =/= 0 andalso
                Request#select_profile.request =:= Cell#cell.request of
                true -> {?PROFILE_INVALID, Cell};
                false -> select_new(Request, Cell)
            end
    end.

%% Admission uses the current configuration epoch and one fixed region of eight capabilities.
-spec select_new(#select_profile{}, #cell{}) -> {hls_nums:u8(), #cell{}}.
select_new(Request, Cell) ->
    if
        Cell#cell.pending -> {?PROFILE_BUSY, Cell};
        Request#select_profile.epoch =/= Cell#cell.epoch -> {?PROFILE_STALE, Cell};
        Request#select_profile.profile > 1 orelse Request#select_profile.request =:= 0 ->
            {?PROFILE_INVALID, Cell};
        Cell#cell.epoch =:= ((1 bsl 32) - 1) -> {?PROFILE_EXHAUSTED, Cell};
        true ->
            {?PROFILE_PENDING, Cell#cell{request = Request#select_profile.request,
                requested_epoch = Request#select_profile.epoch,
                requested_profile = Request#select_profile.profile, pending = true}}
    end.

%% The request's status and the currently confirmed configuration remain separate fields.
-spec live_status(#cell{}) -> hls_nums:u8().
live_status(Cell) ->
    case Cell#cell.pending of true -> ?PROFILE_PENDING; false -> ?PROFILE_APPLIED end.

%% Neither mask permits use outside this actuator's statically owned eight-capability region.
-spec profile_mask(hls_nums:u8()) -> hls_nums:u8().
profile_mask(Profile) ->
    case Profile of 0 -> 0; _ -> 16#fe end.

%% Status is bounded observation, not a history or an exactly-once guarantee after reset.
-spec report(hls_nums:u8(), hls_nums:u32(), #cell{}) -> #profile_status{}.
report(Status, Request, Cell) ->
    #profile_status{status = Status, request = Request, epoch = Cell#cell.epoch,
        profile = Cell#cell.profile, enabled = profile_mask(Cell#cell.profile)}.

-doc "Declares one closed actuator with generated host calls/casts and separate reply/effect outputs; no test-specific command translation is permitted.".
-spec topology() -> map().
topology() ->
    #{version => 1, actors => #{actuator => ?MODULE}, families => #{}, startup => [],
      route_relations => [],
      ingresses => [{commands, {rectangle, [1, 1]},
          [{all, [select_profile, query_profile, apply_profile, controller_failure],
              [{actor, actuator, {at, [0, 0]}}]}]}],
      externals => [{effects, out, [profile_applied]}, {replies, out, [profile_status]}],
      routes => [{{actuator, effect}, [{external, effects}]},
          {{actuator, reply}, [{external, replies}]}]}.
