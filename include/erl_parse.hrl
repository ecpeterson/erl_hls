%%%% erl_parse.hrl
%%%%
%%%% Record definitions for erl_parse structs, as much as one can.

-record(tuple, {
    anno,
    slots
}).

-record(atom, {
    anno,
    atom
}).

-record(var, {
    anno,
    name :: atom()
}).

-record(integer, {
    anno,
    value
}).

-record(clause, {
    anno,
    patterns,
    guards,
    body
}).

-record(attribute, {
    anno,
    kind :: atom(),
    arg
}).

-record(remote, {
    anno,
    module,
    name,
    args
}).

-record(match, {
    anno,
    pattern,
    rhs
}).

-record(typed_record_field, {
    record_field,
    type
}).

-record(record_field, {
    anno,
    name,
    default  % NOTE: can also appear without this!
}).

%% record and record creation both share 'record'
%% unary and binary ops both share 'op'
