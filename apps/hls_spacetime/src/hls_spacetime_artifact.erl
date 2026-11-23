-module(hls_spacetime_artifact).
-include_lib("kernel/include/file.hrl").
-moduledoc """
Local artifact IO for capture producers and the spacetime command. Raw ETF preserves the library's typed maps between Erlang stages; JSON is the browser boundary. Inputs are trusted local artifacts, not network messages. Validation remains in hls_spacetime and the native importer.
""".
%% Shared offline workflow IO, with no simulator or vendor-tool invocation.
-export([read/1, write_bundle/2, write_catalogue/2]).
-define(MAX_BYTES, 268435456).

-doc "Reads one trusted, uncompressed ETF file, at most 256 MiB, without creating atoms. Loads the fixed schema modules first. Rejects compressed terms, trailing bytes, functions, ports, pids and references. This is an interchange reader, not schema validation or an authenticity check.".
-spec read(file:filename_all()) -> term().
read(Path) ->
    {ok, #file_info{type = regular, size = Size}} = file:read_file_info(Path),
    true = Size =< ?MAX_BYTES,
    lists:foreach(
        fun(Module) -> {module, Module} = code:ensure_loaded(Module) end,
        [
            hls_spacetime,
            hls_spacetime_storage,
            hls_spacetime_physical,
            hls_spacetime_native,
            hls_spacetime_import,
            hls_spacetime_sdf
        ]
    ),
    {ok, Bytes} = file:read_file(Path),
    true = byte_size(Bytes) =:= Size,
    case Bytes of
        <<131, 80, _/binary>> -> error({spacetime_artifact, compressed_term});
        <<131, _/binary>> -> ok;
        _ -> error({spacetime_artifact, not_etf})
    end,
    {Term, Used} = binary_to_term(Bytes, [safe, used]),
    true = Used =:= byte_size(Bytes),
    ok = data(Term),
    Term.

-doc "Validates a bundle and writes bundle.etf, bundle.json, summary.json and their SHA-256 inventory into a new directory. Existing directories reject; failures leave diagnostic prefixes without a complete manifest. Returns the validation summary.".
-spec write_bundle(hls_spacetime:bundle(), file:filename_all()) -> hls_spacetime:summary().
write_bundle(Bundle, Directory) ->
    Summary = hls_spacetime:validate(Bundle),
    write(Directory, [
        {"bundle.etf", term_to_binary(Bundle, [deterministic])},
        {"bundle.json", hls_spacetime:encode(Bundle)},
        {"summary.json", json:encode(Summary)}
    ]),
    Summary.

-doc "Writes a catalogue returned by hls_spacetime_import:read/3 as catalogue.etf with a SHA-256 inventory into a new directory. Checks its physical schema; the importer and caller still own native input verification.".
-spec write_catalogue(hls_spacetime_physical:physical(), file:filename_all()) ->
    hls_spacetime_physical:summary().
write_catalogue(Catalogue = #{build := Build}, Directory) ->
    Summary = hls_spacetime_physical:validate(Build, #{}, Catalogue),
    write(Directory, [{"catalogue.etf", term_to_binary(Catalogue, [deterministic])}]),
    Summary.

%% Only ordinary data is permitted at the trusted local interchange boundary.
-spec data(term()) -> ok.
data(Term) when is_atom(Term); is_binary(Term); is_number(Term) -> ok;
data(Term) when is_list(Term) -> lists:foreach(fun data/1, Term);
data(Term) when is_tuple(Term) -> data(tuple_to_list(Term));
data(Term) when is_map(Term) ->
    maps:foreach(
        fun(K, V) ->
            data(K),
            data(V)
        end,
        Term
    );
data(_) ->
    error({spacetime_artifact, non_data_term}).

%% The complete inventory is written last; a prefix never claims success.
-spec write(file:filename_all(), [{file:filename(), iodata()}]) -> ok.
write(Directory, Files) ->
    ok = file:make_dir(Directory),
    Entries = [write_file(Directory, Name, Bytes) || {Name, Bytes} <- Files],
    Manifest = #{format => spacetime_artifacts, schema => 1, complete => true, files => Entries},
    ok = file:write_file(filename:join(Directory, "manifest.json"), json:encode(Manifest), [
        exclusive
    ]).

%% Bound each serialized object, retaining exact bytes and content identities.
-spec write_file(file:filename_all(), file:filename(), iodata()) -> map().
write_file(Directory, Name, Data) ->
    Bytes = iolist_to_binary(Data),
    true = byte_size(Bytes) =< ?MAX_BYTES,
    ok = file:write_file(filename:join(Directory, Name), Bytes, [exclusive]),
    #{
        file => list_to_binary(Name),
        bytes => byte_size(Bytes),
        sha256 => binary:encode_hex(crypto:hash(sha256, Bytes), lowercase)
    }.
