%%%% hls_reduction
%%%%
%%%% Pure actor-local reduction state for the hls_statem CPU reference.

-module(hls_reduction).
-moduledoc """
Tracks one open, bounded actor-local reduction.

`open/4` installs either a contribution count or a fixed expected member set.
`contribute/5,6` distinguish a temporarily mismatched reduction key from
definite protocol errors, leaving postponement policy to the owning scheduler.
Accepted values are combined by `Module:reduce(Name, Accumulator, Value)`.
The caller may rely only on the commutative-monoid contract supplied when the
reduction is opened, not on the reference runtime's arrival-order fold.

The final accepted contribution returns a private completion event and no
longer returns open reduction state. This makes closing linear: the owning
scheduler must deliver that event exactly once before opening another window.
""".

-export([open/4, contribute/5, contribute/6, info/1]).
-export_type([
    reduction/0,
    population/0,
    monoid/0,
    completion_event/0,
    open_error/0,
    contribution_error/0
]).

-define(MAX_PARTICIPANTS, 255).

-record(reduction, {
    name :: atom(),
    key :: term(),
    population :: {count, 1..?MAX_PARTICIPANTS} | {members, [term()]},
    expected = #{} :: map(),
    seen = #{} :: map(),
    remaining :: 1..?MAX_PARTICIPANTS,
    accumulator :: term()
}).

-opaque reduction() :: #reduction{}.
-type population() ::
    {count, 1..?MAX_PARTICIPANTS} |
    {members, [term(), ...]}.
-type monoid() :: {commutative_monoid, Identity :: term()}.
-type completion_event() :: {
    reduction_complete,
    Name :: atom(),
    Key :: term(),
    Accumulator :: term()
}.
-type open_error() :: invalid_name | invalid_population | invalid_monoid.
-type contribution_error() ::
    wrong_mode |
    {duplicate_member, term()} |
    {unexpected_member, term()}.

-doc "Opens one nonempty bounded reduction.".
-spec open(atom(), term(), population(), monoid()) ->
    {ok, reduction()} | {error, open_error()}.
open(Name, Key, Population, {commutative_monoid, Identity})
        when is_atom(Name) ->
    case normalize_population(Population) of
        {ok, Normalized, Expected, Count} ->
            {ok, #reduction{
                name = Name,
                key = Key,
                population = Normalized,
                expected = Expected,
                remaining = Count,
                accumulator = Identity
            }};
        error ->
            {error, invalid_population}
    end;
open(Name, _Key, _Population, _Monoid) when not is_atom(Name) ->
    {error, invalid_name};
open(_Name, _Key, _Population, _Monoid) ->
    {error, invalid_monoid}.

-doc """
Offers one count-mode contribution.

An incomplete acceptance returns `{pending, Reduction}`. The final one returns
`{complete, CompletionEvent}`. `mismatch` identifies a different name or key;
definite population errors return `{error, Reason}`. Rejections do not mutate
the opaque input reduction.
""".
-spec contribute(module(), term(), term(), term(), reduction()) ->
    mismatch |
    {pending, reduction()} |
    {complete, completion_event()} |
    {error, contribution_error()}.
contribute(
    Module,
    Name,
    Key,
    Value,
    Reduction = #reduction{name = ExpectedName, key = ExpectedKey}
) ->
    case matches(Name, Key, ExpectedName, ExpectedKey) of
        true -> contribute_count(Module, Value, Reduction);
        false -> mismatch
    end.

-doc "Offers one fixed-member contribution.".
-spec contribute(module(), term(), term(), term(), term(), reduction()) ->
    mismatch |
    {pending, reduction()} |
    {complete, completion_event()} |
    {error, contribution_error()}.
contribute(
    Module,
    Name,
    Key,
    Member,
    Value,
    Reduction = #reduction{name = ExpectedName, key = ExpectedKey}
) ->
    case matches(Name, Key, ExpectedName, ExpectedKey) of
        true -> contribute_member(Module, Member, Value, Reduction);
        false -> mismatch
    end.

-doc "Returns non-value diagnostics for an open reduction.".
-spec info(reduction()) -> map().
info(#reduction{
    name = Name,
    key = Key,
    population = Population,
    remaining = Remaining
}) ->
    #{
        name => Name,
        key => Key,
        population => Population,
        received => population_size(Population) - Remaining,
        remaining => Remaining
    }.

normalize_population({count, Count})
        when is_integer(Count), Count >= 1, Count =< ?MAX_PARTICIPANTS ->
    {ok, {count, Count}, #{}, Count};
normalize_population({members, Members})
        when is_list(Members),
             length(Members) >= 1,
             length(Members) =< ?MAX_PARTICIPANTS ->
    Expected = maps:from_list([{Member, true} || Member <- Members]),
    case map_size(Expected) =:= length(Members) of
        true -> {ok, {members, Members}, Expected, length(Members)};
        false -> error
    end;
normalize_population(_Population) ->
    error.

population_size({count, Count}) -> Count;
population_size({members, Members}) -> length(Members).

matches(Name, Key, ExpectedName, ExpectedKey) ->
    Name =:= ExpectedName andalso Key =:= ExpectedKey.

contribute_count(_Module, _Value, #reduction{
    population = {members, _Members}
}) ->
    {error, wrong_mode};
contribute_count(Module, Value, Reduction = #reduction{
    population = {count, _Count}
}) ->
    accept(Module, Value, Reduction).

contribute_member(_Module, _Member, _Value, #reduction{
    population = {count, _Count}
}) ->
    {error, wrong_mode};
contribute_member(Module, Member, Value, Reduction = #reduction{
    population = {members, _Members},
    expected = Expected,
    seen = Seen
}) ->
    case {maps:is_key(Member, Expected), maps:is_key(Member, Seen)} of
        {false, _} ->
            {error, {unexpected_member, Member}};
        {true, true} ->
            {error, {duplicate_member, Member}};
        {true, false} ->
            accept(
                Module,
                Value,
                Reduction#reduction{seen = Seen#{Member => true}}
            )
    end.

accept(Module, Value, Reduction = #reduction{
    name = Name,
    key = Key,
    remaining = Remaining,
    accumulator = Accumulator
}) ->
    Combined = Module:reduce(Name, Accumulator, Value),
    case Remaining of
        1 ->
            {complete, {reduction_complete, Name, Key, Combined}};
        _ ->
            {pending, Reduction#reduction{
                remaining = Remaining - 1,
                accumulator = Combined
            }}
    end.
