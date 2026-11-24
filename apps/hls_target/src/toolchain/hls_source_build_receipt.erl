-module(hls_source_build_receipt).
-include_lib("kernel/include/file.hrl").
-moduledoc """
Validates one source-build v2 compilation receipt against its retained release.

The check binds the exact source recipe, external-tool request, product inventory, realized
implementation, provenance and retained product/RTL bytes. It establishes local correlation under
the trusted build-directory boundary, not producer authenticity or hardware behavior.
""".

-export([validate/2]).
-export_type([receipt/0]).

-define(MAX_MANIFEST_BYTES, 16777216).
-define(MAX_PRODUCT_BYTES, 268435456).
-define(MAX_FILES, 512).

-doc "A checked realized implementation and the complete release-relative RTL inventory.".
-type receipt() :: #{implementation := binary(), rtl := [binary(), ...]}.

-doc "Validates `compiled.json`, its retained `source-build.json` and every declared product/RTL byte. `SourceBuild` is the exact source recipe consumed by the caller. Malformed, cross-linked or changed input raises `{source_build_receipt, Reason}`.".
-spec validate(file:filename_all(), binary()) -> receipt().
validate(Directory, SourceBuild) when is_binary(SourceBuild) ->
    try checked(Directory, SourceBuild) of
        Receipt -> Receipt
    catch
        error:{source_build_receipt, _} = Reason -> error(Reason);
        _:_ -> error({source_build_receipt, invalid_receipt})
    end;
validate(_Directory, _SourceBuild) ->
    error({source_build_receipt, invalid_source_recipe}).

%% Check every identity relation before returning the implementation to an observer.
-spec checked(file:filename_all(), binary()) -> receipt().
checked(Directory, SourceBuild) ->
    SourceHash = hash(SourceBuild),
    SourceBuild = read(filename:join(Directory, "source-build.json"), ?MAX_MANIFEST_BYTES),
    #{
        <<"version">> := 2,
        <<"metadata">> := Metadata,
        <<"provenance">> := Provenance,
        <<"units">> := SourceUnits,
        <<"rtl">> := SourceRtl
    } = Source = json:decode(SourceBuild),
    ok = provenance(Provenance),
    true = map_size(Source) >= 3,
    SourceRtl = source_rtl(SourceUnits),
    Compiled = json:decode(
        read(filename:join(Directory, "compiled.json"), ?MAX_MANIFEST_BYTES)
    ),
    ExpectedKeys = lists:sort([
        <<"build_request">>,
        <<"eligible">>,
        <<"implementation">>,
        <<"metadata">>,
        <<"native_measured">>,
        <<"products">>,
        <<"provenance">>,
        <<"rtl">>,
        <<"source_build_sha256">>,
        <<"units">>,
        <<"version">>,
        <<"xls_tools">>
    ]),
    ExpectedKeys = lists:sort(maps:keys(Compiled)),
    #{
        <<"version">> := 2,
        <<"source_build_sha256">> := SourceHash,
        <<"metadata">> := Metadata,
        <<"provenance">> := Provenance,
        <<"build_request">> := BuildRequest,
        <<"products">> := Products,
        <<"implementation">> := Implementation,
        <<"xls_tools">> := XlsTools,
        <<"rtl">> := Rtl,
        <<"eligible">> := false,
        <<"native_measured">> := false
    } = Compiled,
    #{
        <<"schema">> := 1,
        <<"sha256">> := RequestIdentity,
        <<"descriptor">> := Request
    } = BuildRequest,
    3 = map_size(BuildRequest),
    #{
        <<"schema">> := 1,
        <<"source_recipe_sha256">> := SourceHash,
        <<"tools">> := XlsTools,
        <<"units">> := RequestUnits,
        <<"rtl">> := SourceRtl
    } = Request,
    true = sha256(RequestIdentity),
    RequestIdentity = json_identity(Request),
    #{
        <<"schema">> := 1,
        <<"files">> := ProductFiles,
        <<"sha256">> := ProductIdentity
    } = Products,
    3 = map_size(Products),
    true = sha256(ProductIdentity),
    ProductIdentity = json_identity(#{<<"schema">> => 1, <<"files">> => ProductFiles}),
    ProductNames = checked_rows(Directory, ProductFiles),
    ProductNames = expected_products(SourceUnits, RequestUnits),
    #{
        <<"schema">> := 1,
        <<"request_sha256">> := RequestIdentity,
        <<"product_sha256">> := ProductIdentity,
        <<"provenance">> := Provenance,
        <<"sha256">> := ImplementationIdentity
    } = Implementation,
    5 = map_size(Implementation),
    true = sha256(ImplementationIdentity),
    ImplementationIdentity = json_identity(maps:without([<<"sha256">>], Implementation)),
    RtlNames = checked_rtl(Directory, SourceRtl, Rtl),
    #{implementation => ImplementationIdentity, rtl => RtlNames}.

%% Validate the closed source-provenance vocabulary used by the v2 emitter.
-spec provenance(term()) -> ok.
provenance(#{<<"kind">> := <<"unplanned">>} = Value) when map_size(Value) =:= 1 ->
    ok;
provenance(
    #{
        <<"kind">> := <<"implementation_plan">>,
        <<"logical_system_sha256">> := Logical,
        <<"implementation_plan_sha256">> := Plan,
        <<"target_projection_sha256">> := Projection
    } = Value
) when map_size(Value) =:= 4 ->
    true = lists:all(fun sha256/1, [Logical, Plan, Projection]),
    ok.

%% Derive the complete external-product set from paired frozen source and request units.
-spec expected_products([map()], [map()]) -> [binary()].
expected_products(SourceUnits, RequestUnits) when
    is_list(SourceUnits), SourceUnits =/= [], is_list(RequestUnits)
->
    true = length(SourceUnits) =:= length(RequestUnits),
    Names = lists:append([
        unit_products(Source, Request)
     || {Source, Request} <- lists:zip(SourceUnits, RequestUnits)
    ]),
    true = length(Names) =< ?MAX_FILES,
    Sorted = lists:sort(Names),
    Sorted = lists:usort(Sorted),
    Sorted.

%% Require the exact relocatable three-command recipe derived from one frozen source unit.
-spec unit_products(map(), map()) -> [binary()].
unit_products(
    Source = #{
        <<"directory">> := Directory,
        <<"role">> := Role,
        <<"source">> := SourcePath,
        <<"top">> := Top,
        <<"module">> := Module,
        <<"output">> := Product,
        <<"dslx_path">> := DslxPath,
        <<"codegen_flags">> := CodegenFlags,
        <<"rtl">> := Rtl
    },
    Request = #{
        <<"directory">> := Directory,
        <<"role">> := Role,
        <<"source">> := SourcePath,
        <<"top">> := Top,
        <<"module">> := Module,
        <<"dslx_path">> := DslxPath,
        <<"codegen_flags">> := CodegenFlags,
        <<"commands">> := Commands
    }
) when map_size(Source) =:= 9, map_size(Request) =:= 8 ->
    lists:foreach(fun relative/1, [Directory, Role, SourcePath, Product | DslxPath ++ Rtl]),
    true = nonempty(Top) andalso nonempty(Module),
    true = is_list(DslxPath) andalso is_list(CodegenFlags) andalso is_list(Rtl),
    true = lists:all(fun nonempty/1, CodegenFlags),
    Raw = filename:join(Directory, <<"raw.ir">>),
    Optimized = filename:join(Directory, <<"optimized.ir">>),
    Commands = [
        #{
            <<"stage">> => <<"convert">>,
            <<"tool">> => <<"ir_converter_main">>,
            <<"arguments">> => [
                <<"--warnings_as_errors=false">>,
                <<"--top=", Top/binary>>,
                <<"--dslx_path=", (join(DslxPath))/binary>>,
                <<"--dslx_stdlib_path=_stdlib">>,
                SourcePath
            ],
            <<"output">> => Raw
        },
        #{
            <<"stage">> => <<"opt">>,
            <<"tool">> => <<"opt_main">>,
            <<"arguments">> => [Raw],
            <<"output">> => Optimized
        },
        #{
            <<"stage">> => <<"codegen">>,
            <<"tool">> => <<"codegen_main">>,
            <<"arguments">> => CodegenFlags ++ [<<"--module_name=", Module/binary>>, Optimized],
            <<"output">> => Product
        }
    ],
    [Raw, Optimized, Product].

%% Reconstruct the source manifest's role inventory from its exact unit order.
-spec source_rtl([map()]) -> map().
source_rtl(Units) when is_list(Units), Units =/= [] ->
    Roles = lists:usort([maps:get(<<"role">>, Unit) || Unit <- Units]),
    maps:from_list([
        {Role,
            lists:append([
                maps:get(<<"rtl">>, Unit)
             || Unit <- Units, maps:get(<<"role">>, Unit) =:= Role
            ])}
     || Role <- Roles
    ]).

%% Join portable DSLX import roots exactly as the Python request encoder does.
-spec join([binary()]) -> binary().
join(Paths) -> iolist_to_binary(lists:join(<<":">>, Paths)).

%% Command arguments and logical names are nonempty byte strings at this boundary.
-spec nonempty(term()) -> boolean().
nonempty(Value) -> is_binary(Value) andalso byte_size(Value) > 0.

%% Require compiled RTL roles and ordered file identities to match the frozen source recipe.
-spec checked_rtl(file:filename_all(), map(), map()) -> [binary()].
checked_rtl(Directory, Expected, Actual) when is_map(Expected), is_map(Actual) ->
    Roles = lists:sort(maps:keys(Expected)),
    Roles = lists:sort(maps:keys(Actual)),
    Names = lists:append([
        begin
            ExpectedNames = maps:get(Role, Expected),
            true = is_list(ExpectedNames) andalso ExpectedNames =/= [],
            ExpectedNames = checked_rows(Directory, maps:get(Role, Actual)),
            ExpectedNames
        end
     || Role <- Roles
    ]),
    Sorted = lists:sort(Names),
    Sorted = lists:usort(Sorted),
    Sorted.

%% Rows are canonical, unique, bounded and checked against the release bytes they name.
-spec checked_rows(file:filename_all(), [map()]) -> [binary()].
checked_rows(Directory, Rows) ->
    true = is_list(Rows) andalso Rows =/= [] andalso length(Rows) =< ?MAX_FILES,
    Names = [
        begin
            #{<<"file">> := Name, <<"sha256">> := Expected} = Row,
            2 = map_size(Row),
            ok = relative(Name),
            true = sha256(Expected),
            Name
        end
     || Row <- Rows
    ],
    Names = lists:sort(Names),
    Names = lists:usort(Names),
    {_Used, Names} = lists:foldl(
        fun(#{<<"file">> := Name, <<"sha256">> := Expected}, {Used, Acc}) ->
            Bytes = read(filename:join(Directory, Name), ?MAX_PRODUCT_BYTES - Used),
            Expected = hash(Bytes),
            {Used + byte_size(Bytes), Acc}
        end,
        {0, Names},
        Rows
    ),
    Names.

%% Match the Python executor's compact sorted-key JSON identity on the pinned OTP toolchain.
-spec json_identity(term()) -> binary().
json_identity(Value) -> hash(iolist_to_binary(json:encode(Value))).

%% Receipt paths are release-relative data, never shell text.
-spec relative(term()) -> ok.
relative(Name) when is_binary(Name), byte_size(Name) > 0 ->
    relative = filename:pathtype(Name),
    false = lists:member(<<"..">>, filename:split(Name)),
    nomatch = re:run(Name, <<"[\\x00-\\x1f\\x7f]">>, [{capture, none}]),
    ok.

%% Read one stable regular file under an explicit allocation bound.
-spec read(file:filename_all(), non_neg_integer()) -> binary().
read(Path, Limit) when Limit >= 0 ->
    {ok, #file_info{size = Size, type = regular}} = file:read_file_info(Path),
    true = Size >= 0 andalso Size =< Limit,
    {ok, Bytes} = file:read_file(Path),
    Size = byte_size(Bytes),
    Bytes.

%% Use one canonical lowercase textual digest shape throughout the receipt.
-spec sha256(term()) -> boolean().
sha256(Value) when is_binary(Value), byte_size(Value) =:= 64 ->
    match =:= re:run(Value, <<"^[0-9a-f]{64}$">>, [{capture, none}]);
sha256(_) ->
    false.

%% Hash exact JSON or retained-file bytes without assigning them semantic authority.
-spec hash(binary()) -> binary().
hash(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
