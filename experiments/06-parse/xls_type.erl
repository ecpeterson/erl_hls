-module(xls_type).
-export([]).

% TODO: might need to provide a side channel arg with recursive type info,
%   probably supplied by a call made at parse transform time?
% TODO: provide new/1 to construct the type? as/2 to convert to this type?
-callback pack(any()) -> binary().
-callback unpack(binary()) -> any().
-callback transpile(atom(), [iolist()]) -> iolist().
-callback new(Descriptor :: [any()]) -> any().
-callback as(Descriptor :: [any()], InValue :: any()) -> OutValue :: any().
