-module(hls_record_codec).
-moduledoc """
Retained host record layouts used by build clients to bind schemas once and encode/decode later. Delegates to hls_record and the current hls_type providers without loading the actor module or rereading source. Descriptors are trusted local compiler outputs, never network inputs.
""".
%% Retained schema construction and validation.
-export([bind/2, width/1, check/1]).

%% Host record codecs.
-export([pack/2, unpack/2]).
%% Shared type contracts.
-export_type([codec/0]).

-doc "A serializable record name, ordered field descriptors and packed width. Provider code is dynamically dispatched; each retained descriptor names a stable encoding contract.".
-opaque codec() :: #{name := atom(), fields := hls_record:fields(), width := non_neg_integer()}.

-doc "Retains a checked record schema and its packed width after checking provider availability and required callbacks. No actor codec or source file is consulted. Compatible provider updates preserve existing constructor meanings; incompatible encodings need a new constructor name or version argument.".
-spec bind(atom(), hls_record:fields()) -> codec().
bind(Name, Fields) ->
    ok = check_providers(Name, Fields),
    #{name => Name, fields => Fields, width => hls_record:width(Name, Fields)}.

-doc "Returns the retained serialized width without loading or calling a provider.".
-spec width(codec()) -> non_neg_integer().
width(#{width := Width}) -> Width.

-doc "Checks current provider availability and total width, then packs the declared record shape. Preserves provider normalization and errors; successful output has the retained width. Callers finish encoding before external I/O or queue admission.".
-spec pack(codec(), term()) -> bitstring().
pack(Codec = #{name := Name, fields := Fields, width := Width}, Value) ->
    ok = check(Codec),
    Bits = hls_record:pack(Value, Name, Fields),
    Width = bit_size(Bits),
    Bits.

-doc "Checks current provider availability and total width, then decodes one retained-width record and returns untouched trailing bits. Short input and provider failures propagate. Framing and canonical-padding checks belong to the caller; they may repack the result before admission.".
-spec unpack(codec(), bitstring()) -> {tuple(), bitstring()}.
unpack(Codec = #{name := Name, fields := Fields, width := Width}, Bits) ->
    ok = check(Codec),
    {RecordBits, Rest} = hls_codec:split(Bits, Width),
    {Value, <<>>} = hls_record:unpack(RecordBits, Name, Fields),
    {Value, Rest}.

-doc "Checks current descriptor providers, their required callbacks and total packed width. This is not a compatibility proof: same-width semantic changes and compensating field-width changes can pass. Helpers are resolved normally at use; session migration and code-upgrade coordination belong to the application.".
-spec check(codec()) -> ok.
check(#{name := Name, fields := Fields, width := Expected}) ->
    ok = check_providers(Name, Fields),
    case hls_record:width(Name, Fields) of
        Expected -> ok;
        Actual -> error({record_codec_width_changed, Name, Expected, Actual})
    end.

%% Only descriptor providers are required here; their helper calls use normal module dispatch.
-spec check_providers(atom(), hls_record:fields()) -> ok.
check_providers(Name, Fields) ->
    lists:foreach(
        fun require_codec/1,
        hls_type:providers({hls_type, hls_record, Name, Fields})
    ).

%% Check exports after loading so an unloaded, available provider remains usable.
-spec require_codec(module()) -> ok.
require_codec(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} -> ok;
        {error, Reason} -> error({record_codec_provider_unavailable, Module, Reason})
    end,
    lists:foreach(
        fun({Name, Arity}) ->
            case erlang:function_exported(Module, Name, Arity) of
                true -> ok;
                false -> error({missing_record_codec_callback, Module, Name, Arity})
            end
        end,
        [{width, 2}, {pack, 3}, {unpack, 3}]
    ).
