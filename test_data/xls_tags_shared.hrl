%%%% Shared tag fragment for repeated-xls_tags compiler fixtures.

-xls_tags([shared]).

-record(shared, {
    value = xls_type:zero() :: xls_nums:u32()
}).
