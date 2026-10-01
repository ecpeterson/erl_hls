%%%% xls_parse_io
%%%%
%%%% Small formatting helpers shared by the XLS parser and renderers.

-module(xls_parse_io).
-moduledoc false.

-export([indent/2]).

-spec indent(iodata(), non_neg_integer()) -> iolist().
indent(Data, Spaces) ->
    Prefix = lists:duplicate(Spaces, $\s),
    Lines = string:split(iolist_to_binary(Data), "\n", all),
    [
        [Prefix, binary_to_list(Line), "\n"]
        || Line <- Lines, Line =/= <<>>
    ].
