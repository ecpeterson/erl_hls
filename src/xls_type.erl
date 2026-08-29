-module(xls_type).
-moduledoc """
 
""".
-export([zero/0, zero/1, select/3, width/1, pack/2, unpack/2, print_type/1]).
-compile(export_all).

%%%
%%% Structure for XLS type descriptors
%%%

-record(xls_type, {
    module,
    name,
    args
}).
-doc "". 
-type descriptor() :: #xls_type{
    module :: module(),
    name :: atom(),
    args :: [arg()]
}.
-type arg() :: integer() | descriptor().

%%%
%%% xls_type behavior
%%%

-doc "Packs a `Value` according to a type `Descriptor`.".
-callback pack(Value :: any(), atom(), [any()]) -> binary().

-doc """
Unpacks a value previously processed by pack/2.  This is usually a sub-call of
an `xls_gs` instance's `unpack/2`.
""".
-callback unpack(Packed :: binary(), atom(), [any()]) -> {Value :: any(), Rest :: binary()}.

-doc """
Converts an Erlang call with XLS embodiments of its arguments to an equivalent
XLS expression.
""".
%% TODO: might need to supply clause state for anonymous variables
-callback transpile(FnName :: atom(), XLSArgs :: [xls_parse:ir()], State :: xls_parse:clause_state()) -> xls_parse:ir().

-doc "Builds an empty Erlang instance of this type.".
-callback zero(TypeName :: atom(), Args :: [arg()]) -> any().

-doc "Emits the corresponding XLS type for the Erlang type descriptor.".
-callback print_type(TypeName :: atom(), Args :: [any()]) -> xls_parse:printable().

-doc "Calculate the bit width of this type when packed.".
-callback width(Name :: atom(), Args :: [any()]) -> integer().

% -doc """
% in-XLS un/pack? or maybe transpiles to `as` but has no Erlang effect?
% """.
% -callback as(Descriptor :: [any()], InValue :: any()) -> OutValue :: any().

%%%
%%% Descriptor-level versions which dispatch on Module
%%%

-spec zero() -> no_return().
-doc """
Type-directed zero-value marker for translated record field defaults.

`xls_pack` replaces this call with `zero/1` using the field's type annotation.
Calling it outside a transformed record declaration is an error.
""".
zero() ->
    error(unexpanded_xls_zero).

-spec zero(descriptor()) -> any().
-doc "". 
zero(#xls_type{module = Module, name = Name, args = Args}) ->
    Module:zero(Name, Args).

%% TODO: Move lowerable non-type operations into an xls_primitives-style
%% module once there is a family of them rather than a single selection.
-doc "Chooses between two values of the same XLS type.".
-spec select(boolean(), T, T) -> T.
select(true, WhenTrue, _WhenFalse) ->
    WhenTrue;
select(false, _WhenTrue, WhenFalse) ->
    WhenFalse.

transpile(select, [Condition, WhenTrue, WhenFalse], _State) ->
    ["if ", Condition, " { ", WhenTrue, " } else { ", WhenFalse, " }"].

-spec width(descriptor()) -> integer().
-doc "". 
width(#xls_type{module = Module, name = Name, args = Args}) ->
    Module:width(Name, Args).

pack(Value, {xls_type, Module, Name, Args}) ->
    Module:pack(Value, Name, Args).

unpack(Binary, {xls_type, Module, Name, Args}) ->
    Module:unpack(Binary, Name, Args).

print_type({xls_type, Module, Name, Args}) ->
    Module:print_type(Name, Args).

%%%
%%% 
%%%

-spec descriptor(erl_parse:af_abstract_type()) -> descriptor().
-doc "". 
descriptor({remote_type, _1, [{atom, _2, Module}, {atom, _3, Name}, Args]}) ->
    {xls_type, Module, Name, [descriptor(Arg) || Arg <- Args]};
descriptor({integer, _1, Integer}) ->
    Integer;
descriptor({atom, _1, Atom}) ->
    Atom.
