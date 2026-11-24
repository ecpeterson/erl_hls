"""Verify the bounded four-Phi RAM history and select one read and multiply for both backends."""

import re
from pathlib import Path

CYCLES = 4096
SELECTED_BIT = 84
FACTOR = 0x2AAAAAAAAB


def require(condition: bool, message: str) -> None:
    """Reject incomplete or contradictory source evidence with its failed obligation."""
    if not condition:
        raise ValueError(message)


def replay(path: Path) -> dict:
    """Check every sampled memory edge and accepted multiply; preserve unknown startup values."""
    require(path.stat().st_size <= 8 << 20, "trace byte limit")
    lines = path.read_text().splitlines()
    # Icarus versions differ in whether they print a separate $finish diagnostic.
    if lines and re.fullmatch(
        r".*transaction_tb.sv:\d+: \$finish called at \d+ \(1ps\)", lines[-1]
    ):
        lines.pop()
    require(
        len(lines) == CYCLES + 1 and lines.pop() == f"END {CYCLES}", "trace coverage"
    )
    unknown = "x" * 135
    contents = [unknown, unknown]
    producer = [None, None]
    last_q = unknown
    last_operand = None
    pending = None
    selected = None
    counts = dict(writes=0, reads=0, collisions=0, accepted=0, changed_products=0)
    for cycle, line in enumerate(lines):
        (
            index,
            resetn,
            we,
            wa,
            re_,
            ra,
            data,
            prior_q,
            valid,
            ready,
            operand,
            product,
            machine,
            negative,
            stage_done,
            old_result,
            q,
            row0,
            row1,
            result,
        ) = line.split()
        require(
            int(index) == cycle and resetn == str(int(cycle >= 4)),
            f"clock/reset C{cycle}",
        )
        require(
            all(
                re.fullmatch(r"[0-9a-fx]{135}", v)
                for v in (data, prior_q, machine, q, row0, row1)
            ),
            f"word encoding C{cycle}",
        )
        require(prior_q == last_q, f"read bus continuity C{cycle}")
        if cycle >= 4:
            require(
                all(v in ("0", "1") for v in (we, re_, valid, ready)),
                f"unknown enable C{cycle}",
            )
        if resetn == "1":
            require(
                stage_done == str(int(valid == ready == "1")),
                f"executor stage enable C{cycle}",
            )
            if stage_done == "0":
                require(result == old_result, f"executor result hold C{cycle}")
        if valid == ready == resetn == "1":
            require(
                bool(re.fullmatch(r"[0-9a-f]{10}", operand))
                and int(operand, 16) < 1 << 38,
                f"unknown or wide operand C{cycle}",
            )
            require(
                bool(re.fullmatch(r"[0-9a-f]{19}", product))
                and int(product, 16) == int(operand, 16) * FACTOR,
                f"multiply C{cycle}",
            )
            require(negative in ("0", "1"), f"unknown product sign C{cycle}")
            magnitude = int(product, 16) >> 41
            expected = (-magnitude if negative == "1" else magnitude) % (1 << 36)
            require(result == f"{expected:09x}", f"captured arithmetic result C{cycle}")
            counts["accepted"] += 1
            if last_operand is not None and operand != last_operand:
                counts["changed_products"] += 1
                if pending and selected is None and machine == prior_q:
                    selected = dict(
                        **pending,
                        resultCycle=cycle,
                        operand=operand,
                        product=product,
                        priorAcceptedOperand=last_operand,
                        requestState=machine,
                        capturedResult=result,
                        priorResult=old_result,
                    )
            last_operand = operand
        pending = None
        expected_q = prior_q
        if re_ == "1":
            require(ra in ("0", "1"), f"unknown read address C{cycle}")
            address = int(ra)
            expected_q = contents[address]
            counts["reads"] += 1
            counts["collisions"] += int(we == "1" and wa == ra)
            if (
                producer[address] is not None
                and "x" not in prior_q + expected_q
                and (int(prior_q, 16) ^ int(expected_q, 16)) & (1 << SELECTED_BIT)
            ):
                pending = dict(
                    writeCycle=producer[address],
                    readCycle=cycle,
                    address=address,
                    value=expected_q,
                    previousOutput=prior_q,
                )
        require(q == expected_q, f"read-first output C{cycle}")
        if we == "1":
            require(wa in ("0", "1"), f"unknown write address C{cycle}")
            contents[int(wa)] = data
            producer[int(wa)] = cycle
            counts["writes"] += 1
        require(contents == [row0, row1], f"post-edge RAM contents C{cycle}")
        last_q = q
    require(
        selected is not None,
        "no changed selected RAM bit with matching accepted executor state",
    )
    return dict(
        cycles=CYCLES,
        ramWidth=540,
        selectedBit=SELECTED_BIT,
        factor=hex(FACTOR),
        counts=counts,
        transaction=selected,
    )
