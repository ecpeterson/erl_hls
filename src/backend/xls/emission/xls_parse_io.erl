%%%% xls_parse_io
%%%%
%%%% Small formatting helpers shared by the XLS parser and renderers.

-module(xls_parse_io).
-moduledoc "Terminal indentation for rendered DSLX iodata, used by xls_dslx and text-only renderer fragments. Lowerers carrying structured failure references use xls_dslx:indent/2 instead, so formatting cannot render away metadata before xls_emitted finalization.".

%% Indent already rendered text, not deferred expression nodes.
-export([indent/2]).

-spec indent(iodata(), non_neg_integer()) -> iolist().
indent(Data, Spaces) ->
    Prefix = lists:duplicate(Spaces, $\s),
    Lines = string:split(iolist_to_binary(Data), "\n", all),
    [
        [Prefix, binary_to_list(Line), "\n"]
     || Line <- Lines, Line =/= <<>>
    ].
