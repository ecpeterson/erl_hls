-module(xls_names_gs_fixture).
-behaviour(hls_gs).
-compile({parse_transform, hls_pack}).
-export([init/1, handle_call/2, handle_cast/2]).
-hls_tags(['Set_Value', 'Get_Value', 'Reply_Value']).
-hls_replies([{'Get_Value', ['Reply_Value']}]).
-record('Set_Value', {'Value' = hls_type:zero() :: hls_nums:u32()}).
-record('Get_Value', {'Key' = hls_type:zero() :: hls_nums:u32()}).
-record('Reply_Value', {'Value' = hls_type:zero() :: hls_nums:u32()}).
-record('Server_Data', {'Value' = hls_type:zero() :: hls_nums:u32()}).

-spec init(any()) -> #'Server_Data'{}.
init([]) -> #'Server_Data'{}.
handle_cast(#'Set_Value'{'Value' = Value}, State) ->
    {noreply, State#'Server_Data'{'Value' = Value}}.
handle_call(#'Get_Value'{}, State = #'Server_Data'{'Value' = Value}) ->
    {reply, #'Reply_Value'{'Value' = Value}, State}.
