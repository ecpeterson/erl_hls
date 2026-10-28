-module(hls_protocol_mixed_schema).
-moduledoc "Concrete retained record and crossing descriptors for mixed BEAM/native sessions. Build-time capture metadata may accompany these views, but runtime codecs and queues need no source programs or planner types.".

-export_type([class/0, link/0, encoder_link/0, decoder_link/0, binding/0]).

-doc "One crossing slot with its compact-frame constraints and retained source/destination record codecs. Port and tag select source messages; the compact codec owns the independent destination selector. Additional physical capture metadata is ignored at runtime.".
-type class() :: #{slot := non_neg_integer(), codec := hls_protocol_codec:plan(),
    port := atom(), tag := atom(), message_bits := non_neg_integer(),
    source_record := hls_record_codec:codec(), destination_record := hls_record_codec:codec(),
    atom() => term()}.

-doc "A retained sender/destination crossing and its checked codec classes. Indices and direction bind queue ownership; additional physical layout metadata is not interpreted by the host codec.".
-type link() :: #{index := non_neg_integer(), source_index := non_neg_integer(),
    destination_index := non_neg_integer(), direction := to_rtl | to_beam,
    source_module := module(), destination_module := module(), classes := [class()], atom() => term()}.

-doc "Source record classes sufficient for encoding without an actor interface or source program. Source module identity is retained metadata; encoding uses the bound record codec.".
-type encoder_link() :: #{source_module := module(), classes := [class()], atom() => term()}.

-doc "Destination record classes sufficient for decoding without reloading the destination actor. The retained record codec and compact-frame constraints remain authoritative.".
-type decoder_link() :: #{destination_module := module(), classes := [class()], atom() => term()}.

-doc "Retained actor, crossing and application codecs checked before opening a mixed session. Other build/attachment fields are ignored; current providers must retain their declared type and encoding contracts.".
-type binding() :: #{actors := #{non_neg_integer() => #{schemas := hls_host_codec:catalog(), atom() => term()}},
    mixed := #{links := [link()], atom() => term()},
    application := hls_protocol_application_schema:application(), atom() => term()}.
