"""EXP010 read-only source integrity and intentional corruption regressions."""
from __future__ import annotations

import copy
import unittest

from tools.validate_exp010_logistics import load_inputs, replay_reference, validate


class EXP010LogisticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas, cls.chains, cls.book = load_inputs()

    def mutation(self, field: str, value: object, expected: str,
                 *, job: bool = False) -> None:
        altered = copy.deepcopy(self.book)
        target = altered["entries"][0]["jobs"][0] if job else altered["entries"][0]
        target[field] = value
        with self.assertRaisesRegex(ValueError, expected):
            validate(self.atlas, self.chains, altered)

    def test_exact_200_manifests_400_jobs_800_host_targets(self) -> None:
        audit = validate(self.atlas, self.chains, self.book)
        self.assertEqual((audit["levels"], audit["jobs"], audit["targets"], audit["domains"]),
                         (200, 400, 800, 8))
        self.assertEqual(audit["patterns"], {"serial": 67, "triage": 67, "crossdock": 66})

    def test_every_source_has_feasible_finite_stock_dispatch(self) -> None:
        for entry in self.book["entries"]:
            replay_reference(entry)

    def test_supply_material_inflation_is_rejected(self) -> None:
        self.mutation("stock", {"spares": 900, "fuel": 900}, "STOCK_OR_DEPOT")

    def test_source_identity_swaps_are_rejected(self) -> None:
        self.mutation("chain_key", "foreign", "SOURCE_DRIFT")
        self.mutation("location_id", "LOC_999", "SOURCE_DRIFT")

    def test_wrong_critical_cargo_and_service_splice_are_rejected(self) -> None:
        self.mutation("cargo", "Unapproved cable", "JOB_SOURCE", job=True)
        self.mutation("linked_service", "FC_999_2", "JOB_SOURCE", job=True)

    def test_deadline_manipulation_is_rejected(self) -> None:
        self.mutation("deadline_ticks", 1000000, "JOB_SOURCE", job=True)

    def test_duplicate_level_and_target_are_rejected(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["entries"][1] = copy.deepcopy(altered["entries"][0])
        with self.assertRaisesRegex(ValueError, "DUPLICATE_OR_FOREIGN"):
            validate(self.atlas, self.chains, altered)
        self.mutation("depot", "LG_002_DEPOT", "STOCK_OR_DEPOT")

    def test_pattern_and_work_order_dependencies_are_source_bound(self) -> None:
        self.mutation("pattern", "triage", "PATTERN_DRIFT")
        changed = copy.deepcopy(self.book)
        changed["entries"][0]["jobs"][1]["requires"] = ""
        with self.assertRaisesRegex(ValueError, "JOB_SOURCE"):
            validate(self.atlas, self.chains, changed)

    def test_manifest_header_authority_is_not_implicitly_trusted(self) -> None:
        altered = copy.deepcopy(self.book)
        altered["authority"] = "CLIENT_APPROVED_LOGISTICS"
        with self.assertRaisesRegex(ValueError, "HEADER"):
            validate(self.atlas, self.chains, altered)


if __name__ == "__main__":
    unittest.main()
