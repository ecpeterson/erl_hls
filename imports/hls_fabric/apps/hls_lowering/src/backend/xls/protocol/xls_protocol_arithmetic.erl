-module(xls_protocol_arithmetic).
-moduledoc "Renders source-completion wiring for checked arithmetic groups inside xls_protocol_network. Selection precedes callback work and results return through registered actor actions; no result queue or separate RTL controller is introduced.".

%% Shared arithmetic state and transition fragments.
-export([state/1, steps/1, updates/1]).

%% Selected actor input wiring.
-export([inputs/2]).

-doc "Declares one bounded round-robin cursor per checked group; zero is its reset value.".
-spec state([map()]) -> iodata().
state(Groups) -> [[name(I), ": bits[", n(W), "],\n"] || #{index := I, cursor_bits := W} <- Groups].

-doc "Emits old-state request arbitration and exactly one selected source-completion call per group. Startup and reset mask grants. The compiler checks all identical source modules before this emitter; receiver-local action structs are reconstructed by named fields.".
-spec steps([map()]) -> iodata().
steps(Groups) ->
    [
        begin
            N = length(Members),
            [First | _] = Members,
            [
                "let ",
                name(G),
                "_pick = arithmetic::select(",
                lists:join(" ++ ", [
                    [
                        "((!io.reset && s.actor_",
                        n(I),
                        ".started && actor_",
                        n(I),
                        "::local_reduce_request(s.actor_",
                        n(I),
                        ".owner, u32:0)) as u1)"
                    ]
                 || I <- lists:reverse(Members)
                ]),
                ", s.",
                name(G),
                " as u32);\n",
                "let ",
                name(G),
                "_raw = match ",
                name(G),
                "_pick.index {\n",
                [
                    ["u32:", n(J), " => s.actor_", n(I), ".owner.machine,\n"]
                 || {J, I} <- lists:enumerate(0, Members)
                ],
                "_ => actor_",
                n(First),
                "::MachineBits:0, };\n",
                "let ",
                name(G),
                "_action = actor_",
                n(First),
                "::local_reduce_action_at(",
                name(G),
                "_raw, u32:0);\n",
                "let ",
                name(G),
                "_next = if io.reset { u32:0 } else if ",
                name(G),
                "_pick.mask != bits[",
                n(N),
                "]:0 {\n",
                "if ",
                name(G),
                "_pick.index + u32:1 == u32:",
                n(N),
                " { u32:0 } else { ",
                name(G),
                "_pick.index + u32:1 }\n",
                "} else { s.",
                name(G),
                " as u32 };\n"
            ]
        end
     || #{index := G, members := Members} <- Groups
    ].

-doc "Registers the cursor after a real grant, or resets it with the enclosing network.".
-spec updates([map()]) -> iodata().
updates(Groups) ->
    [
        [name(G), ": ", name(G), "_next as bits[", n(W), "],\n"]
     || #{index := G, cursor_bits := W} <- Groups
    ].

-doc "Renders a receiver's resolved one-hot grant and named action fields. none supplies no extra inputs. Network planning binds the exact group/member; this renderer does not search topology membership. The action is ignored unless this member was granted.".
-spec inputs(non_neg_integer(), none | #{group := non_neg_integer(), member := non_neg_integer()}) ->
    iodata().
inputs(_, none) ->
    [];
inputs(I, #{group := G, member := J}) ->
    [
        "completion_granted: ",
        name(G),
        "_pick.mask[",
        n(J),
        "+:u1],\n",
        "completion_action: actor_",
        n(I),
        "::LocalAction {\n",
        [
            [F, ": ", name(G), "_action.", F, ",\n"]
         || F <- ["private_machine", "dispatched", "directive", "phase_boundary"]
        ],
        "},\n"
    ].

%% Group identifiers come only from deterministic fresh-plan enumeration.
-spec name(non_neg_integer()) -> string().
name(I) -> "arithmetic_" ++ n(I).

%% Checked dimensions and indices are the only generated numeric literals.
-spec n(non_neg_integer()) -> string().
n(I) -> integer_to_list(I).
