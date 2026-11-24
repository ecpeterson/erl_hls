-module(hls_protocol_application_schema).
-moduledoc """
Application builders and runtime codecs share these concrete descriptor types. They describe actor ownership, geometry and record codecs without carrying an executable source program or renderer.

Concrete retained host descriptors shared by application builders and runtime codecs. These types contain logical ownership, geometry and record codecs; they require neither compiler programs nor hardware plans.
""".

%% Runtime identity and codec contracts are independent of source configuration types.
-export_type([
    id/0,
    device/0,
    endpoint/0,
    actor/0,
    partition/0,
    event/0,
    binding/0,
    application/0, application/1,
    control_view/0,
    event_view/0
]).

-doc "A retained logical actor, ingress or external identity, independent of wire endpoints.".
-type id() :: hls_logical_identity:id().

-doc "An application-chosen device key, independent of host addresses and process identities.".
-type device() :: term().

-doc "A nonzero 16-bit host or service endpoint.".
-type endpoint() :: 1..((1 bsl 16) - 1).

-doc "One globally indexed actor with its canonical exact-or-family instance identity, checked owner, declared outputs and retained record codecs.".
-type actor() :: #{
    id := id(),
    module := module(),
    outputs := [atom()],
    mailbox_capacity := pos_integer(),
    identity := hls_actor_identity:id(),
    index := non_neg_integer(),
    device := device(),
    schemas := hls_host_codec:catalog(),
    output_schemas := #{atom() => [atom()]}
}.

%% Geometry selection needs only these fields; source and placement metadata may also be retained.
-type recipient() :: #{
    index := non_neg_integer(),
    device := device(),
    point := [non_neg_integer()],
    targets := [id()],
    schemas := hls_host_codec:catalog(),
    atom() => term()
}.

%% Wire target selectors are independent of actor indices and transport endpoints.
-type target() :: #{id := id(), selector := non_neg_integer(), schemas := [atom()]}.

%% Coordinates and schemas suffice for runtime selection; no topology expansion is repeated.
-type ingress() :: #{
    id := id(),
    shape := [pos_integer()],
    targets := [target()],
    bindings := [recipient()],
    frame_layout => hls_frame_layout:layout()
}.

%% Source ports and recipients use canonical actor-instance identities, not Erlang addresses.
-type route() :: #{
    source := {hls_actor_identity:id(), atom()},
    recipients := [hls_actor_identity:id() | {external, id()}],
    delivery := direct | coupled | buffered | queued | best_effort
}.

-doc "Checked host inventory and rectangle ingress, without sessions or generated hardware plans.".
-type partition() :: #{
    frame_layout := hls_frame_layout:layout(),
    actors := [actor()],
    routes := [route()],
    ingresses := [ingress()]
}.

-doc "An external stream with unambiguous message selectors and retained producer codecs.".
-type event() :: #{id := id(), port := string(), schemas := #{byte() => hls_host_codec:schema()}}.

-doc "Source-checked endpoints and event codecs before optional gateway rendering and attachment identity.".
-type binding() :: #{
    host := endpoint(),
    control := endpoint(),
    ingress := id(),
    events := #{endpoint() => event()},
    frame_layout := hls_frame_layout:layout(),
    activation := explicit_start
}.

-doc "Host partition and device bindings parameterized by the caller's concrete endpoint descriptor.".
-type application(Binding) :: #{partition := partition(), devices := #{device() => Binding}}.

-doc "The source-checked application binding before hardware emission.".
-type application() :: application(binding()).

-doc "The concrete geometry and record codecs needed for control selection. Other retained application fields are ignored; omitted frame_layout selects the established default capacity.".
-type control_view() :: #{
    partition := #{
        ingresses := [ingress()],
        frame_layout => hls_frame_layout:layout(),
        atom() => term()
    },
    atom() => term()
}.

-doc "The concrete endpoint, ordinary-frame layout and producer schemas needed to decode an event. Other build and attachment metadata is not interpreted.".
-type event_view() :: #{
    devices := #{
        device() => #{
            host := endpoint(),
            events := #{endpoint() => event()},
            frame_layout := hls_frame_layout:layout(),
            atom() => term()
        }
    },
    atom() => term()
}.
