%%%% Shared tag fragment for repeated-hls_tags compiler fixtures.

-hls_tags([shared]).

-record(shared, {
    value = hls_type:zero() :: hls_nums:u32()
}).
