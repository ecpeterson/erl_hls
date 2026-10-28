-module(xls_named_bits).
-moduledoc "Internal hls_type provider for nominal DSLX bit types already declared by generated layouts such as gather progress. xls_struct_codec uses these descriptors for typed packing; host values are unsigned encoded integers and enum membership remains the declaring code's responsibility. Source-language calls to this provider are unsupported.".
-behavior(hls_type).
%% Construct compiler-owned local or imported nominal descriptors.
-export([local/2, qualified/3]).
%% hls_type value layout and host codec callbacks.
-export([width/2, zero/2, pack/3, unpack/3]).
%% hls_type target spelling and rejection of source operations.
-export([print_type/2, transpile/3]).

-doc "Describes a positive-width bit type already declared in the current generated module. Name must be a compiler-owned DSLX identifier, not an expression.".
-spec local(atom(), pos_integer()) -> hls_type:descriptor().
local(Name, Width) when Width > 0 ->
    {hls_type, ?MODULE, local, [Name, Width]}.

-doc "Describes a positive-width bit type in an imported DSLX module. Module and Name must be compiler-owned identifiers; the caller supplies the import.".
-spec qualified(atom(), atom(), pos_integer()) -> hls_type:descriptor().
qualified(Module, Name, Width) when Width > 0 ->
    {hls_type, ?MODULE, qualified, [Module, Name, Width]}.

-doc "Returns the dense serialized width, which is also the logical bit width.".
-spec width(local | qualified, [hls_type:arg()]) -> pos_integer().
width(local, [_Name, Width]) -> Width;
width(qualified, [_Module, _Name, Width]) -> Width.

-doc "Returns encoded zero; callers own any nominal enum-validity requirements.".
-spec zero(local | qualified, [hls_type:arg()]) -> 0.
zero(_Kind, _Args) -> 0.

-doc "Packs an unsigned encoded integer through the ordinary numeric provider. Values outside the declared width are rejected; no enum membership check is added.".
-spec pack(term(), local | qualified, [hls_type:arg()]) -> bitstring().
pack(Value, Kind, Args) ->
    hls_type:pack(Value, unsigned(Kind, Args)).

-doc "Decodes one unsigned integer of the declared width and leaves the remaining bitstring untouched.".
-spec unpack(bitstring(), local | qualified, [hls_type:arg()]) -> {non_neg_integer(), bitstring()}.
unpack(Packed, Kind, Args) ->
    hls_type:unpack(Packed, unsigned(Kind, Args)).

-doc "Renders the nominal DSLX name; the default hls_type bit-cast codec supplies conversions.".
-spec print_type(local | qualified, [hls_type:arg()]) -> iodata().
print_type(local, [Name, _Width]) -> atom_to_list(Name);
print_type(qualified, [Module, Name, _Width]) -> [atom_to_list(Module), "::", atom_to_list(Name)].

-doc "Rejects source calls: these descriptors belong to compiler-generated structures, not the source-language type API.".
-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) -> no_return().
transpile(Operation, _Args, _State) ->
    error({internal_type_operation, Operation}).

%% Reuse the established integer domain and little-endian host representation.
-spec unsigned(local | qualified, [hls_type:arg()]) -> hls_type:descriptor().
unsigned(Kind, Args) -> hls_nums:uN(width(Kind, Args)).
