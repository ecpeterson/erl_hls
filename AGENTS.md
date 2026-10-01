# Repository instructions

Read [STYLE.md](STYLE.md) before changing code or documentation. Every PR must follow its source-contract, brevity and documentation rules.

Run the checks in [docs/source-quality.md](docs/source-quality.md), plus tests appropriate to the change. Complete contracts for changed declarations; use the CI audit to find remaining migration work. Keep agent working notes in `yap/`, outside `docs/`. Do not claim the whole tree is documented while the audit reports gaps.

Use the evidence labels in [docs/formal-contracts.md](docs/formal-contracts.md). A simulation is a witness; bounded formal checks must state their horizon. Proof claims must identify the property, quantified domain, assumptions and trust boundary.
