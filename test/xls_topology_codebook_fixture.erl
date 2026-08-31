-module(xls_topology_codebook_fixture).

-behavior(xls_statem).

-xls_outputs([north, east, west, south, syndrome]).
-xls_mailbox_capacity(5).
-xls_tags([
    phi,
    anyon_move,
    phi0,
    phenom_config,
    phenom_request,
    phenom_query,
    phenom_data,
    phenom_anyon
]).
-xls_tags([fixture_extra]).

-export([handle_cast/3, handle_enter/3, init/1]).

init([]) ->
    {ok, waiting, #{}}.

handle_enter(_OldPhase, waiting, Data) ->
    {Data, []}.

handle_cast(_Message, waiting, Data) ->
    {waiting, Data, consume}.
