"""Finite report-validation fixtures; no subprocesses, RTL jobs, network or board access."""

import copy
import unittest
from typing import Any

from domain_board_observations import validate


def status(index: int, session: int, epoch: int, request: int) -> dict[str, Any]:
    """Make a healthy canonical status with explicit role and lifetime identity."""
    return {'kind': 'board', 'abi': 1, 'role': index + 1, 'status': 'ok', 'request': request,
            'domain_session': session, 'endpoint_session': session, 'incarnation': epoch,
            'health': {'carrier_armed': True, 'carrier_fault': 0, 'domain_attached': bool(session),
                       'endpoint_attached': bool(session), 'domain_wire_fault': False,
                       'endpoint_wire_fault': False, 'router_fault': False, 'phase_code': 0}}


def fixture() -> tuple[list[dict[str, Any]], dict[str, Any], list[dict[str, Any]]]:
    """Use different actor IDs and incarnations on the two boards so swapped scope cannot accidentally pass."""
    domains = [{'index': 0, 'actors': [2, 4]}, {'index': 1, 'actors': [7, 9]}]
    result = {'incarnations': [{'domain_incarnations': [11, 21]}, {'domain_incarnations': [12, 25]}]}
    observations = []
    for index in (0, 1):
        session = 100 + index
        observations.append({'file': f'board{index}-bootstrap.etf', 'value': {
            'cold': status(index, 0, 0, 1), 'established': status(index, session, 0, 2)}})
        for lifetime in (0, 1):
            epoch = result['incarnations'][lifetime]['domain_incarnations'][index]
            values = [{'kind': 'inspection', 'request': 3 + lifetime * 3 + offset, 'status': 'ok',
                       'session': session, 'incarnation': epoch, 'actor': actor, 'value': [offset + 1] + [0] * 15}
                      for offset, actor in enumerate(domains[index]['actors'])]
            observations.append({'file': f'board{index}-inspection-{epoch}.etf', 'value': {
                'status': status(index, session, epoch, 5 + lifetime * 3), 'values': values}})
    return domains, result, observations


class ObservationTests(unittest.TestCase):
    """Require selected-profile coverage and reject superficially successful replies from the wrong scope."""

    def test_process_two_boards_two_lifetimes(self) -> None:
        """Both exact scopes produce four independently counted inspection records."""
        report = validate('process', *fixture())
        self.assertEqual(len(report['records']), 4)
        self.assertEqual(sum(row['reply_count'] for row in report['records']), 8)

    def test_missing_record_or_actor(self) -> None:
        """Missing a whole board/lifetime, an actor, or a bootstrap cannot pass."""
        for missing in ('record', 'actor', 'bootstrap'):
            with self.subTest(missing=missing):
                domains, result, rows = fixture()
                if missing == 'record':
                    rows.pop()
                elif missing == 'bootstrap':
                    rows.pop(0)
                else:
                    rows[1]['value']['values'].pop()
                with self.assertRaises(ValueError):
                    validate('process', domains, result, rows)

    def test_process_rejects_unsupported_none_accepts_zero(self) -> None:
        """Unsupported is profile-sensitive and always requires a canonical zero snapshot."""
        domains, result, rows = fixture()
        for row in rows:
            for value in row['value'].get('values', []):
                value['status'], value['value'] = 'unsupported', [0] * 16
        with self.assertRaises(ValueError):
            validate('process', domains, result, rows)
        self.assertTrue(validate('none', domains, result, rows)['passed'])
        rows[1]['value']['values'][0]['value'][0] = 1
        with self.assertRaises(ValueError):
            validate('none', domains, result, rows)

    def test_wrong_reply_scope(self) -> None:
        """Session, incarnation, actor, kind and duplicate request identities are checked independently."""
        for field, wrong in [('session', 101), ('incarnation', 12), ('actor', 7), ('kind', 'board'), ('request', 1)]:
            with self.subTest(field=field):
                domains, result, rows = fixture()
                rows[1]['value']['values'][0][field] = wrong
                with self.assertRaises(ValueError):
                    validate('process', domains, result, rows)

    def test_wrong_board_and_status_scope(self) -> None:
        """A healthy response from the other physical role or lifetime cannot stand in for the selected board."""
        for field, wrong in [('role', 2), ('incarnation', 21), ('domain_session', 101)]:
            with self.subTest(field=field):
                domains, result, rows = fixture()
                rows[1]['value']['status'][field] = wrong
                with self.assertRaises(ValueError):
                    validate('process', domains, result, rows)

    def test_empty_or_duplicate_snapshots(self) -> None:
        """Zero-only process evidence, repeated actors and repeated files each reject."""
        for mutation in ('zero', 'actor', 'file', 'bytes'):
            with self.subTest(mutation=mutation):
                domains, result, rows = fixture()
                values = rows[1]['value']['values']
                if mutation == 'zero':
                    for value in values:
                        value['value'] = [0] * 16
                elif mutation == 'actor':
                    values[1]['actor'] = values[0]['actor']
                elif mutation == 'file':
                    rows.append(copy.deepcopy(rows[1]))
                else:
                    values[0]['value'] = [1] * 15
                with self.assertRaises(ValueError):
                    validate('process', domains, result, rows)

    def test_wrong_record_epoch_and_nonadvancing_lifetime(self) -> None:
        """File names and recorded incarnation vectors must agree and progress on each board."""
        domains, result, rows = fixture()
        rows[1]['file'] = 'board0-inspection-21.etf'
        with self.assertRaises(ValueError):
            validate('process', domains, result, rows)
        domains, result, rows = fixture()
        result['incarnations'][1]['domain_incarnations'][0] = 11
        with self.assertRaises(ValueError):
            validate('process', domains, result, rows)


if __name__ == '__main__':
    unittest.main()
