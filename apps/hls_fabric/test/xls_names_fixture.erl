-module(xls_names_fixture).
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, 'Gathering'/3, 'Complete'/3, reduce/3]).

-hls_data('Actor_Data').
-hls_tags(['Input_Value', 'Output_Value']).
-hls_phases(['Gathering', 'Complete']).
-hls_outputs(['Result']).
-hls_mailbox_capacity(2).

-record('Input_Value', {
    'Key' = hls_type:zero() :: hls_nums:u32(),
    'Value' = hls_type:zero() :: hls_nums:u32()
}).
-record('Output_Value', {'Value' = hls_type:zero() :: hls_nums:u32()}).
-record('Actor_Data', {
    'Key' = hls_type:zero() :: hls_nums:u32(),
    'Value' = hls_type:zero() :: hls_nums:u32()
}).
-record('Fold_Value', {'Value' = hls_type:zero() :: hls_nums:u32()}).

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {'ok','Gathering',#'Actor_Data'{'Key'::17}}.
init([]) -> {ok, 'Gathering', #'Actor_Data'{'Key' = 17}}.

-doc "Accepts mixed-case contribution schemas in the namespace witness.".
-spec 'Gathering'(enter, hls_statem:phase(), #'Actor_Data'{}) -> hls_statem:enter_result(#'Actor_Data'{});
    (cast, tuple(), #'Actor_Data'{}) -> hls_statem:cast_result(#'Actor_Data'{});
    (internal, hls_statem:reduction_complete(), #'Actor_Data'{}) -> hls_statem:internal_result(#'Actor_Data'{}).
'Gathering'(enter, _, Data) ->
    {Data, [{open_reduction, 'SUM', Data#'Actor_Data'.'Key', {count, 2},
        {commutative_monoid, #'Fold_Value'{'Value' = 0}}}]};
'Gathering'(cast, Message = #'Input_Value'{'Key' = Key}, Data) ->
    {'Gathering', Data, {contribute, 'SUM', Key,
        #'Fold_Value'{'Value' = value(increment(Message))}}};
'Gathering'(internal, {reduction_complete, 'SUM', Key, #'Fold_Value'{'Value' = Value}},
        Data = #'Actor_Data'{'Key' = Key}) ->
    {'Complete', Data#'Actor_Data'{'Value' = Value}, consume}.

-doc "Handles the namespace fixture's private completion event.".
-spec 'Complete'(enter, hls_statem:phase(), #'Actor_Data'{}) -> hls_statem:enter_result(#'Actor_Data'{});
    (cast, tuple(), #'Actor_Data'{}) -> hls_statem:cast_result(#'Actor_Data'{}).
'Complete'(enter, _, Data) ->
    #'Actor_Data'{'Value' = Value} = Data,
    {Data, [{cast, 'Result', #'Output_Value'{'Value' = Value}}]};
'Complete'(cast, #'Input_Value'{}, Data) -> {'Complete', Data, consume}.

-doc "Combines fixture contributions using its declared bounded arithmetic.".
-spec reduce('SUM',#'Fold_Value'{'Value'::number()},#'Fold_Value'{'Value'::number()}) -> #'Fold_Value'{}.
reduce('SUM', #'Fold_Value'{'Value' = A}, #'Fold_Value'{'Value' = B}) ->
    #'Fold_Value'{'Value' = hls_nums:wrap(hls_nums:u32(), A + B)}.

%% Applies the fixture's typed increment operation.
-spec increment(#'Input_Value'{}) -> #'Input_Value'{}.
increment(Message = #'Input_Value'{'Value' = Value}) ->
    Message#'Input_Value'{'Value' = hls_nums:wrap(hls_nums:u32(), Value + 1)}.

%% Extracts the fixture value through a typed helper.
-spec value(#'Input_Value'{}) -> hls_nums:u32().
value(Message) ->
    case Message of
        #'Input_Value'{'Value' = Value} -> Value
    end.
