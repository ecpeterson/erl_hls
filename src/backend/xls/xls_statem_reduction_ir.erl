%%%% xls_statem_reduction_ir
%%%%
%%%% Closed, typed description of actor-local reductions.  Source syntax and
%%%% locations are deliberately absent: consumers see only values that are
%%%% sufficient to render or summarize the reduction implementation.

-module(xls_statem_reduction_ir).
-moduledoc false.

-export([
    new/4,
    interface/1,
    layout/1,
    site_count/1,
    max_population/1,
    max_member_count/1,
    type_width/1,
    site_width/1,
    remaining_width/1,
    member_width/1,
    storage_width/1,
    interface_storage_width/1
]).

-export_type([
    expression/0,
    type_ref/0,
    population/0,
    contribution/0,
    site/0,
    reducer/0,
    reduction/0
]).

-type expression() :: #{
    body := iolist(),
    result := iolist()
}.
-type field() :: #{
    name := atom(),
    type := hls_type:descriptor()
}.
-type type_ref() :: #{
    kind := record,
    name := atom(),
    dslx_type := string(),
    fields := [field()]
}.
-type population() ::
    #{mode := count, size := 1..255} |
    #{mode := members, size := 1..255, members := [0..16#ffffffff]}.
-type contribution() :: #{
    tag := atom(),
    build := expression(),
    source_transportable := boolean(),
    source_capture_total := boolean(),
    transport := none | expression()
}.
-type site() :: #{
    id := non_neg_integer(),
    phase := atom(),
    name := atom(),
    population := population(),
    key := expression(),
    identity := expression(),
    contributions := [contribution(), ...],
    completion := expression()
}.
-type reducer() :: #{
    name := atom(),
    body := iolist(),
    result := iolist()
}.
-type reduction() :: #{
    data := type_ref(),
    accumulator := type_ref(),
    sites := [site(), ...],
    reducers := [reducer(), ...]
}.

-spec new(type_ref(), type_ref(), [site(), ...], [reducer(), ...]) ->
    reduction().
new(Data, Accumulator, Sites, Reducers) ->
    ok = validate_type_ref(data, Data),
    ok = validate_type_ref(accumulator, Accumulator),
    ok = validate_sites(Sites),
    ok = validate_reducers(Sites, Reducers),
    #{
        data => Data,
        accumulator => Accumulator,
        sites => Sites,
        reducers => Reducers
    }.

-spec site_count(reduction()) -> pos_integer().
site_count(#{sites := Sites}) ->
    length(Sites).

-spec max_population(reduction()) -> 1..255.
max_population(#{sites := Sites}) ->
    lists:max([
        maps:get(size, maps:get(population, Site))
        || Site <- Sites
    ]).

-spec max_member_count(reduction()) -> 0..255.
max_member_count(#{sites := Sites}) ->
    lists:max([0 | [
        maps:get(size, Population)
        || Site <- Sites,
           Population <- [maps:get(population, Site)],
           maps:get(mode, Population) =:= members
    ]]).

-spec site_width(reduction()) -> pos_integer().
site_width(Reduction) ->
    unsigned_width(site_count(Reduction) - 1).

-spec remaining_width(reduction()) -> pos_integer().
remaining_width(Reduction) ->
    unsigned_width(max_population(Reduction)).

-spec member_width(reduction()) -> pos_integer().
member_width(Reduction) ->
    max(1, max_member_count(Reduction)).

-spec type_width(type_ref() | map()) -> non_neg_integer().
type_width(#{fields := Fields}) ->
    lists:sum([hls_type:width(maps:get(type, Field)) || Field <- Fields]).

-spec storage_width(reduction()) -> pos_integer().
storage_width(Reduction) ->
    maps:get(total_bits, layout(Reduction)).

-spec layout(reduction()) -> #{
    status_bits := 2,
    site_bits := pos_integer(),
    key_bits := 32,
    remaining_bits := pos_integer(),
    member_bits := pos_integer(),
    accumulator_bits := non_neg_integer(),
    total_bits := pos_integer()
}.
layout(Reduction = #{accumulator := Accumulator}) ->
    StatusBits = 2,
    KeyBits = 32,
    AccumulatorBits = type_width(Accumulator),
    SiteBits = site_width(Reduction),
    RemainingBits = remaining_width(Reduction),
    MemberBits = member_width(Reduction),
    Total = StatusBits + SiteBits + KeyBits + RemainingBits +
        MemberBits + AccumulatorBits,
    #{
        status_bits => StatusBits,
        site_bits => SiteBits,
        key_bits => KeyBits,
        remaining_bits => RemainingBits,
        member_bits => MemberBits,
        accumulator_bits => AccumulatorBits,
        total_bits => Total
    }.

-spec interface(reduction()) -> map().
interface(#{
    accumulator := Accumulator,
    sites := Sites,
    reducers := Reducers
}) ->
    #{
        accumulator => public_type_ref(Accumulator),
        sites => [public_site(Site) || Site <- Sites],
        reducers => [maps:get(name, Reducer) || Reducer <- Reducers]
    }.

public_type_ref(Type) ->
    maps:with([name, fields], Type).

-spec interface_storage_width(map()) -> pos_integer().
interface_storage_width(#{accumulator := Accumulator, sites := Sites}) ->
    StatusBits = 2,
    KeyBits = 32,
    SiteBits = unsigned_width(length(Sites) - 1),
    RemainingBits = unsigned_width(lists:max([
        maps:get(size, maps:get(population, Site)) || Site <- Sites
    ])),
    MemberBits = max(1, lists:max([0 | [
        maps:get(size, Population)
        || Site <- Sites,
           Population <- [maps:get(population, Site)],
           maps:get(mode, Population) =:= members
    ]])),
    StatusBits + SiteBits + KeyBits + RemainingBits + MemberBits +
        type_width(Accumulator).

public_site(Site) ->
    Contributions = maps:get(contributions, Site),
    #{
        id => maps:get(id, Site),
        phase => maps:get(phase, Site),
        name => maps:get(name, Site),
        population => maps:get(population, Site),
        contributions => [maps:get(tag, Contribution)
            || Contribution <- Contributions],
        source_transportable => lists:all(fun(Contribution) ->
            maps:get(source_transportable, Contribution)
        end, Contributions),
        source_capture_total => lists:all(fun(Contribution) ->
            maps:get(source_capture_total, Contribution)
        end, Contributions)
    }.

validate_type_ref(_Context, #{
    kind := record,
    name := Name,
    dslx_type := DslxType,
    fields := Fields
}) when is_atom(Name), is_list(DslxType), is_list(Fields) ->
    lists:foreach(fun validate_field/1, Fields),
    ok.

validate_field(#{name := Name, type := _Type}) when is_atom(Name) ->
    ok.

validate_sites(Sites) when is_list(Sites), Sites =/= [] ->
    IDs = [maps:get(id, Site) || Site <- Sites],
    ExpectedIDs = lists:seq(0, length(Sites) - 1),
    case IDs of
        ExpectedIDs -> ok;
        _ -> error({invalid_hls_statem_reduction_site_ids,
            ExpectedIDs, IDs})
    end,
    Phases = [maps:get(phase, Site) || Site <- Sites],
    require_unique(reduction_phase, Phases),
    lists:foreach(fun validate_site/1, Sites),
    ok.

validate_site(#{
    id := ID,
    phase := Phase,
    name := Name,
    population := Population,
    key := Key,
    identity := Identity,
    contributions := Contributions,
    completion := Completion
}) when is_integer(ID), ID >= 0, is_atom(Phase), is_atom(Name),
        is_list(Contributions), Contributions =/= [] ->
    ok = validate_population(Population),
    ok = validate_expression(key, Key),
    ok = validate_expression(identity, Identity),
    ok = validate_expression(completion, Completion),
    Tags = [maps:get(tag, Contribution) || Contribution <- Contributions],
    require_unique(reduction_contribution_tag, Tags),
    lists:foreach(fun validate_contribution/1, Contributions),
    ok.

validate_population(#{mode := count, size := Size})
        when is_integer(Size), Size >= 1, Size =< 255 ->
    ok;
validate_population(#{mode := members, size := Size, members := Members})
        when is_integer(Size), Size >= 1, Size =< 255, is_list(Members),
             length(Members) =:= Size ->
    case lists:all(fun is_u32/1, Members) andalso
            length(Members) =:= length(lists:usort(Members)) of
        true -> ok;
        false -> error({invalid_hls_statem_reduction_members, Members})
    end.

validate_contribution(#{
    tag := Tag,
    build := Build,
    source_transportable := true,
    source_capture_total := SourceCaptureTotal,
    transport := Transport
}) when is_atom(Tag), is_boolean(SourceCaptureTotal) ->
    ok = validate_expression(contribution, Build),
    validate_expression(transport_contribution, Transport);
validate_contribution(#{
    tag := Tag,
    build := Build,
    source_transportable := false,
    source_capture_total := SourceCaptureTotal,
    transport := none
}) when is_atom(Tag), is_boolean(SourceCaptureTotal) ->
    validate_expression(contribution, Build).

validate_expression(_Context, #{body := Body, result := Result}) ->
    try
        _ = iolist_size(Body),
        _ = iolist_size(Result),
        ok
    catch
        error:badarg ->
            error({invalid_hls_statem_reduction_expression, Body, Result})
    end.

validate_reducers(Sites, Reducers) when is_list(Reducers) ->
    Names = [maps:get(name, Reducer) || Reducer <- Reducers],
    require_unique(reducer, Names),
    Expected = lists:usort([maps:get(name, Site) || Site <- Sites]),
    case lists:sort(Names) of
        Expected -> ok;
        Actual -> error({incomplete_hls_statem_reducers, Expected, Actual})
    end,
    lists:foreach(fun validate_reducer/1, Reducers),
    ok.

validate_reducer(#{name := Name, body := Body, result := Result})
        when is_atom(Name) ->
    validate_expression(reducer, #{body => Body, result => Result}).

require_unique(Kind, Values) ->
    case length(Values) =:= length(lists:usort(Values)) of
        true -> ok;
        false -> error({duplicate_hls_statem_reduction_value, Kind, Values})
    end.

is_u32(Value) ->
    is_integer(Value) andalso Value >= 0 andalso Value =< 16#ffffffff.

unsigned_width(MaxValue) when MaxValue >= 0 ->
    unsigned_width(MaxValue, 1).

unsigned_width(MaxValue, Width) when MaxValue < (1 bsl Width) ->
    Width;
unsigned_width(MaxValue, Width) ->
    unsigned_width(MaxValue, Width + 1).
