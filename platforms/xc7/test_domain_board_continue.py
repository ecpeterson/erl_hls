"""Reviewed continuation regressions without mapping, routing, assembly or board calls."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from application import domain_board_continue as continuation


def fixture(root: Path) -> tuple[Path,Path]:
    """Retain a complete whole-image map with its original component rejection."""
    image = root / 'image-process-role0-2'; image.mkdir(); (image / 'map').mkdir()
    continuation.board.save(image / 'inputs.json',{'inputs':{}})
    (image / 'map/netlist.json').write_text('{}\n')
    continuation.board.save(image / 'map/resources.json',{'mapped':{'complete':True},'bounds':{'passes':True}})
    continuation.board.save(image / 'map/link-screen.json',{'passes':False})
    result = {'success':True,'changed_inputs':[],'whole_image_passes':True,
        'component_screen_passes':False,'route_admitted':False,
        'input_manifest_sha256':continuation.board.digest(image / 'inputs.json')}
    for name,key in (('netlist.json','netlist_sha256'),('resources.json','resources_sha256'),
                     ('link-screen.json','link_screen_sha256')):
        result[key] = continuation.board.digest(image / 'map' / name)
    continuation.board.save(image / 'map/result.json',result)
    review = root / 'review.json'
    continuation.board.save(review,{'schema':'hls_board_route_disposition_v2',
        'component_screen_override_only':True,'component_cost_established':False,
        'synthesis_repeat':False,'route_attempts_per_role':1,'routing_settings_unchanged':True,
        'whole_image_budgets_unchanged':True,'physical_board_access_authorized_now':False,
        'user_instruction':'Proceed with full images.','selected_images':[{
            'path':str(image), 'input_manifest_sha256':continuation.board.digest(image / 'inputs.json'),
            'map_result_sha256':continuation.board.digest(image / 'map/result.json')}]})
    return image,review


class DomainBoardContinuationTests(unittest.TestCase):
    """Only the explicit component exception may change derived admission."""

    def test_absent_or_mismatched_review(self) -> None:
        """Missing review and a review selecting another image stop before preparation."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); image,review = fixture(root)
            with self.assertRaises(FileNotFoundError):
                continuation.prepare(image,root / 'missing.json')
            value = json.loads(review.read_text()); value['selected_images'][0]['path'] = str(root / 'other-image')
            continuation.board.save(review,value)
            with self.assertRaisesRegex(ValueError,'does not select'):
                continuation.prepare(image,review)
            self.assertFalse(image.with_name(image.name + '-route-1').exists())

    def test_whole_image_failure_cannot_be_overridden(self) -> None:
        """User component disposition does not relax the retained whole-image fit gate."""
        with tempfile.TemporaryDirectory() as temporary:
            image,review = fixture(Path(temporary).resolve())
            path = image / 'map/result.json'; result = json.loads(path.read_text())
            result['whole_image_passes'] = False; continuation.board.save(path,result)
            decision = json.loads(review.read_text())
            decision['selected_images'][0]['map_result_sha256'] = continuation.board.digest(path)
            continuation.board.save(review,decision)
            with self.assertRaisesRegex(ValueError,'whole-image map'):
                continuation.prepare(image,review)

    def test_same_basename_does_not_reuse_disposition(self) -> None:
        """An otherwise identical map at a different resolved path has no admission."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            image,review = fixture(root)
            other = root / 'another-campaign'; other.mkdir()
            same_name,_ = fixture(other)
            self.assertEqual(image.name,same_name.name)
            with self.assertRaisesRegex(ValueError,'does not select'):
                continuation.prepare(same_name,review)
            self.assertFalse(same_name.with_name(same_name.name + '-route-1').exists())

    def test_changed_reviewed_identities_stop_preparation(self) -> None:
        """Even semantically harmless changes to either reviewed file invalidate admission."""
        for name in ('inputs.json','map/result.json'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                image,review = fixture(Path(temporary).resolve())
                path = image / name
                path.write_text(path.read_text() + '\n')
                with self.assertRaisesRegex(ValueError,'reviewed image identity changed'):
                    continuation.prepare(image,review)
                self.assertFalse(image.with_name(image.name + '-route-1').exists())

    def test_legacy_name_only_review_is_rejected(self) -> None:
        """The former basename-only format cannot silently fall back to weak matching."""
        with tempfile.TemporaryDirectory() as temporary:
            image,review = fixture(Path(temporary).resolve())
            decision = json.loads(review.read_text())
            decision.update(schema='hls_board_route_disposition_v1',selected_images=[image.name])
            continuation.board.save(review,decision)
            with self.assertRaisesRegex(ValueError,'explicit route disposition'):
                continuation.prepare(image,review)

    def test_receipt_preserves_original_rejection_and_binds_review(self) -> None:
        """One derived admission retains failed component evidence and detects later review edits."""
        with tempfile.TemporaryDirectory() as temporary:
            image,review = fixture(Path(temporary).resolve())
            original = (image / 'map/result.json').read_bytes()
            output = continuation.prepare(image,review)
            continuation.verify(output)
            derived = json.loads((output / 'map/result.json').read_text())
            self.assertTrue(derived['route_admitted'])
            self.assertFalse(derived['component_screen_passes'])
            self.assertFalse(derived['original_route_admitted'])
            self.assertEqual((image / 'map/result.json').read_bytes(),original)
            with self.assertRaises(FileExistsError): continuation.prepare(image,review)
            review.write_text(review.read_text() + '\n')
            with patch.object(continuation.board,'phase') as execute:
                with self.assertRaisesRegex(ValueError,'changed continuation'):
                    continuation.phase(output,'route')
                execute.assert_not_called()


if __name__ == '__main__':
    unittest.main()
