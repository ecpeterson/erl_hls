"""Compare retained repetition results without importing a test entry point."""


def compare(actual: dict, expected: dict, width: int) -> None:
    """Compare every sender through the common fence and the final readout."""
    assert actual['fence'] == expected['fence']
    assert actual['replies'] == expected['replies']
    assert sorted(actual['corrections']) == sorted(expected['corrections'])
    for x in range(width):
        assert [event for event in actual['events']
                if event[0] == x and event[2] <= actual['fence']] == [
                    event for event in expected['events']
                    if event[0] == x and event[2] <= expected['fence']], x
    assert actual['descriptors_closed']
