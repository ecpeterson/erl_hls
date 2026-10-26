-module(xls_actor_program).
-moduledoc "An immutable in-process snapshot of one complete checked actor compilation. Rendering, planning and entry-effect consumers share the same source lowering without rereading files.".
-export([from_file/2, from_file/3, spec/1, plan/1, entry_effects/1]).
-export_type([program/0, entry_effect/0]).

%% The constructor owns the pair; consumers cannot supply a rendering artifact
%% and an independently selected or modified planning sidecar through this API.
-record(program, {spec :: xls_actor_codegen:spec(), plan :: xls_statem_plan:plan()}).

-doc "Complete source snapshot created only by from_file/2 or from_file/3. Retain it unchanged in process; saved or caller-constructed terms are not compilation inputs. Later file edits require a new compilation.".
-opaque program() :: #program{}.

-doc "One ordered entry effect with its phase and layout identity. All original effect and field metadata is retained; storage offsets and slices are meaningful within that layout, preserving established field sharing.".
-type entry_effect() :: #{phase := atom(), layout := non_neg_integer(),
    order := non_neg_integer(), port := atom(), tag := atom(), fields := [map()],
    atom() => term()}.

-doc "Freshly parses and lowers the complete actor with ordinary source options. Returns one source-bound rendering/planning pair; invalid source fails in ordinary lowering. There is no constructor from supplied artifacts or alternatives.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context()) -> program().
from_file(Filename, Options) -> from_file(Filename, Options, hls_frame_layout:default()).

-doc "Compiles one complete source snapshot with an explicit checked ordinary-frame layout; the same layout binds both rendering and planning.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context(),
    hls_frame_layout:layout()) -> program().
from_file(Filename, Options, Layout) ->
    {Spec, Plan} = xls_statem_plan:from_file(Filename, Options, Layout),
    #program{spec = Spec, plan = Plan}.

-doc "Returns the complete ordinary rendering artifact from the snapshot, without rereading source. Editing the returned map does not change the program.".
-spec spec(program()) -> xls_actor_codegen:spec().
spec(#program{spec = Spec}) -> Spec.

-doc "Returns the complete planning sidecar from the same compilation. This view does not revalidate current files; use xls_statem_plan:validate/3 when consuming a saved plan.".
-spec plan(program()) -> xls_statem_plan:plan().
plan(#program{plan = Plan}) -> Plan.

-doc "Lists every ordered effect in every entry layout across all phases. Preserves full typed field, constant, known-bit, slice and storage-sharing metadata without selecting reachable or successful alternatives. Empty layouts have no effects; evaluation and failure obligations remain in spec/1 and plan/1. Non-program inputs are rejected.".
-spec entry_effects(program()) -> [entry_effect()].
entry_effects(#program{spec = #{entries := Entries}}) ->
    [Effect#{phase => Phase, layout => Layout, order => Order}
        || #{layouts := Layouts} <- Entries,
            #{phase := Phase, layout := Layout, storage := #{effects := Effects}} <- Layouts,
            {Order, Effect} <- lists:enumerate(0, Effects)].
