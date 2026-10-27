-module(hls_record_codec).
-moduledoc "Retained record schemas with checked host-code dependencies. Values are trusted local compiler outputs, independent of actor module loading and never accepted from the network.".
-export([bind/2, width/1, pack/2, unpack/2, check/1]).
-export_type([codec/0]).

-doc "A serializable record name, ordered field descriptors, packed width and loaded-code fingerprints. The record schema is retained; provider implementations must remain unchanged during use.".
-opaque codec() :: #{name := atom(), fields := hls_record:fields(), width := non_neg_integer(),
    providers := #{module() => binary()}}.

-doc "Binds a checked record schema to its loaded host providers and their declared transitive helpers. Captures the packed width and rejects unavailable providers, missing codec callbacks or invalid dependency declarations. No actor codec or source file is consulted. Providers must declare hidden dependencies and avoid mutable external state or concurrent code reload during a call.".
-spec bind(atom(), hls_record:fields()) -> codec().
bind(Name, Fields) ->
    Providers = hls_type:providers({hls_type, hls_record, Name, Fields}),
    Identities = dependencies([hls_type | Providers], #{}),
    lists:foreach(fun require_codec/1, Providers),
    Codec = #{name => Name, fields => Fields, width => hls_record:width(Name, Fields),
        providers => Identities},
    ok = check(Codec),
    Codec.

-doc "Returns the retained serialized width without loading or calling a provider.".
-spec width(codec()) -> non_neg_integer().
width(#{width := Width}) -> Width.

-doc "Checks provider identities, then packs the exact declared record shape with the ordinary field codecs. Preserves provider normalization and errors; successful output has the retained width. Callers must finish encoding before external I/O or queue admission.".
-spec pack(codec(), term()) -> bitstring().
pack(Codec = #{name := Name, fields := Fields, width := Width}, Value) ->
    ok = check(Codec),
    Bits = hls_record:pack(Value, Name, Fields),
    Width = bit_size(Bits),
    Bits.

-doc "Checks provider identities, then decodes one retained-width record and returns untouched trailing bits. Short input or provider decoding failures propagate. Framing and canonical-padding checks belong to the caller; they may repack the result before admission.".
-spec unpack(codec(), bitstring()) -> {tuple(), bitstring()}.
unpack(Codec = #{name := Name, fields := Fields, width := Width}, Bits) ->
    ok = check(Codec),
    {RecordBits, Rest} = hls_codec:split(Bits, Width),
    {Value, <<>>} = hls_record:unpack(RecordBits, Name, Fields),
    {Value, Rest}.

-doc "Rejects a missing or changed provider/helper before invoking any record codec callback. Loaded BEAM identities are compared, not source files or code-path contents. This detects sequential reloads; callers must exclude concurrent reload for the duration of encoding, decoding and subsequent admission.".
-spec check(codec()) -> ok.
check(#{providers := Providers}) ->
    maps:foreach(fun(Module, Expected) ->
        case fingerprint(Module) of
            Expected -> ok;
            _ -> error({stale_record_codec_provider, Module})
        end
    end, Providers).

%% Every declared helper is fingerprinted once, even through a dependency cycle.
-spec dependencies([module()], #{module() => binary()}) -> #{module() => binary()}.
dependencies([], Bound) -> Bound;
dependencies([Module | Rest], Bound) when is_map_key(Module, Bound) ->
    dependencies(Rest, Bound);
dependencies([Module | Rest], Bound) ->
    Identity = fingerprint(Module),
    Helpers = case erlang:function_exported(Module, codec_dependencies, 0) of
        true -> declared_dependencies(Module, Module:codec_dependencies());
        false -> []
    end,
    dependencies(Helpers ++ Rest, Bound#{Module => Identity}).

%% Dependency declarations cross the user-provider boundary and must be module names.
-spec declared_dependencies(module(), term()) -> [module()].
declared_dependencies(Module, Helpers) when is_list(Helpers) ->
    case lists:all(fun is_atom/1, Helpers) of
        true -> Helpers;
        false -> error({invalid_codec_dependencies, Module, Helpers})
    end;
declared_dependencies(Module, Other) -> error({invalid_codec_dependencies, Module, Other}).

%% Use the loaded image: a beam file on the path may differ from current VM code.
-spec fingerprint(module()) -> binary().
fingerprint(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} -> Module:module_info(md5);
        {error, Reason} -> error({record_codec_provider_unavailable, Module, Reason})
    end.

%% Hidden helpers need no type callbacks; descriptor providers do.
-spec require_codec(module()) -> ok.
require_codec(Module) ->
    lists:foreach(fun({Name, Arity}) ->
        case erlang:function_exported(Module, Name, Arity) of
            true -> ok;
            false -> error({missing_record_codec_callback, Module, Name, Arity})
        end
    end, [{width, 2}, {pack, 3}, {unpack, 3}]).
