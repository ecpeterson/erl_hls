-module(xls_protocol_application).
-moduledoc "Installs the concrete DSLX gateway and emits only its application configuration constants.".
-export([emit/1, write/2]).

-doc "Writes gateway.x and application_config.x exclusively into a caller-owned directory. Framing and ordering stay in the shared gateway; the separately connected activation bridge supplies actual start completion.".
-spec write(map(),file:filename()) -> ok.
write(Binding, Directory) ->
    hls_generated_files:write_into(#{files => emit(Binding), result => ok}, Directory).

-doc "Returns gateway.x unchanged from the checked adapter and application_config.x containing typed endpoint-count, identity and address constants. Creates no files and substitutes no DSLX program text.".
-spec emit(map()) -> hls_generated_files:files().
emit(#{identity := Identity, host := Host, control := Control, events := Events,
        control_adapter := #{gateway_source := Source}}) ->
    {ok, Gateway} = file:read_file(filename:join(code:priv_dir(hls_fabric), Source)),
    Words = [{"ID" ++ integer_to_list(I), "u64", Word}
        || {I, Word} <- lists:enumerate(0, [W || <<W:64/little>> <= Identity])],
    Config = [constant(Name, Type, Value) || {Name, Type, Value} <-
        [{"EVENTS", "u32", map_size(Events)} | Words] ++
        [{"HOST", "u16", Host}, {"CONTROL", "u16", Control}]],
    #{"gateway.x" => Gateway, "application_config.x" => ["// Bound application identity, endpoint count and addresses.\n", Config]}.

%% Only checked scalar values cross the generated boundary; all behavior is handwritten DSLX.
-spec constant(string(), string(), non_neg_integer()) -> iodata().
constant(Name, Type, Value) ->
    ["pub const ", Name, " = ", Type, ":",
     integer_to_list(Value), ";\n"].
