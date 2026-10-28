-module(xls_record_codegen).
-moduledoc "Renders resolved Erlang records for actor/server lowerers through the generic xls_struct_codec layout machinery. hls_records and hls_type own source resolution and provider semantics; this adapter supplies the checked generated names, struct declaration and physical-stream codecs.".
%% Render a resolved record and its stream conversions.
-export([declaration/1, decoder/1, encoder/1]).

-doc "Emits a public DSLX struct from a checked source record. Field types must be resolved and generated names validated; referenced provider types must be declared or imported.".
-spec declaration(hls_source:record_declaration()) -> iodata().
declaration(Record = {attribute, _, record, {Name, _}}) ->
    xls_struct_codec:declaration(xls_names:record_type(Name), layout(Record)).

-doc "Emits the record's public NAME_from_bits decoder. Inputs retain Erlang field order and may include trailing frame padding; their width must cover the record's complete serialized layout.".
-spec decoder(hls_source:record_declaration()) -> iodata().
decoder(Record = {attribute, _, record, {Name, _}}) ->
    xls_struct_codec:decoder(
        xls_names:record_type(Name),
        xls_names:record_codec(Name) ++ "_from_bits",
        layout(Record)
    ).

-doc "Emits the record's public bits_from_NAME encoder. Field order, provider codecs and provider padding follow the checked source layout.".
-spec encoder(hls_source:record_declaration()) -> iodata().
encoder(Record = {attribute, _, record, {Name, _}}) ->
    xls_struct_codec:encoder(
        xls_names:record_type(Name),
        "bits_from_" ++ xls_names:record_codec(Name),
        layout(Record)
    ).

-doc "Derives a physical-stream layout for a checked source record, retaining declared field order, zero-width fields and provider padding.".
-spec layout(hls_source:record_declaration()) -> xls_struct_codec:layout().
layout(Record) ->
    xls_struct_codec:layout(hls_records:fields(Record), stream).
