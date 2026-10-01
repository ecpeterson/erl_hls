%%%% phenom_syndrome_cell.erl
%%%%
%%%% One syndrome cell from a request-paced phenomenological-noise experiment.

-module(phenom_syndrome_cell).
-moduledoc """
A source-aware syndrome cell which supplies noise events to one phi cell.

## Protocol

Configuration starts the first round by casting a `phenom_query` to each of
the four neighboring data cells. Four distinct `phenom_data` responses are
combined by parity. Their quiet bits are ANDed with the syndrome source's own
quiet state, and the completed result is retained in `announcing`.

The paired phi cell sends one `phenom_request` for that completed step. The
request releases the retained detection event and neighborhood quiet
certificate as one `phenom_anyon`, then starts computation of the following
step. The source can therefore compute one result while phi processes the
preceding result, but it cannot run a second step ahead or fill the phi
mailbox with unrequested announcements.

There is deliberately no timer in this actor. Phi requests provide the credit
which advances the one-result lookahead, so the CPU reference process and
generated module associate the same PRNG draw with each step. Configuration
and all protocol messages share the module's one framed input channel; the
five named outputs are separate, backpressured channels in generated hardware.

## Measurement noise

Before participating, the cell must receive a nonzero `xorshift32` seed and a
`u32` threshold. Once the fourth data response arrives, the generator advances
exactly once. A measurement error is present when the new random word is below
the threshold. The announced event is the parity of the data responses, the
current measurement error, and the previous round's measurement error. Thus a
one-round measurement fault appears at both of its temporal boundaries.

The threshold is a runtime message until the generated topology can supply
static per-instance configuration. A host should configure every syndrome
before allowing its paired phi cell to issue the first request.

A `noise_cutoff` names the first quiet step. It is consumed immediately when
received before that step's random decision. At and after the boundary the
measurement contribution is zero and the PRNG no longer advances. The first
quiet announcement can still contain the trailing edge of a preceding
measurement fault.

## Source labels and capacity

Queries label the sender as seen by the recipient: a query sent north names
its source as `south`, and so on. Data responses follow the same convention.
The source mask rejects duplicate or invalid participants, so completion does
not depend on cross-sender arrival order.

The five-slot mailbox can retain four responses for the result being computed
plus an early request for that result. A completed result lives in actor state,
not in the paired phi actor's mailbox.
""".

%% Shared protocol implementation; the default has four spatial neighbors.
-include("phenom_syndrome_cell_impl.hrl").
