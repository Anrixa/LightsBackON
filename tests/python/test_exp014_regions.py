"""EXP014 A03 independent static geometry, source fidelity and mutation gates."""
from __future__ import annotations

import copy
import json
import unittest

from tools.validate_exp014_regions import (
    ATLAS, CELLS, HALF, PROTECTED, STANDOFF,
    choose, clearance, positions, read_recipes, slot_clear, validate,
)


class EXP014RegionalFacilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
        cls.recipes = read_recipes()

    def test_25_geometrically_distinct_regions_and_all_200_site_slots(self) -> None:
        result = validate(self.atlas, self.recipes)
        self.assertTrue(result["ok"])
        self.assertEqual(result["regional_geometry_packages"], 25)
        self.assertEqual(result["noncosmetic_facility_silhouettes"], 25)
        self.assertEqual(result["distinct_environmental_cues"], 25)
        self.assertEqual(result["audited_source_levels"], 200)
        self.assertEqual(result["preserved_source_tasks"], 1000)
        self.assertGreaterEqual(result["minimum_static_station_standoff_m"], STANDOFF)
        self.assertFalse(result["collision_or_reachability_certified"])
        self.assertFalse(result["human_controller_or_hardware_certified"])
        self.assertFalse(result["release_certified"])

    def test_recolor_and_rename_cannot_supply_new_geometry(self) -> None:
        edited = copy.deepcopy(self.recipes)
        edited["REG_02"]["tone"] = "#111111"
        edited["REG_02"]["forms"] = list(edited["REG_01"]["forms"])
        with self.assertRaisesRegex(ValueError, "COSMETIC_ONLY_VARIETY"):
            validate(self.atlas, edited)

    def test_region_and_location_risk_splices_are_refused(self) -> None:
        altered = copy.deepcopy(self.atlas)
        altered["regions"][0]["hazard"] = "new fabricated hazard"
        with self.assertRaisesRegex(ValueError, "RISK_DRIFT"):
            validate(altered, self.recipes)
        altered = copy.deepcopy(self.atlas)
        altered["locations"][16]["risk"] = self.recipes["REG_01"]["risk"]
        with self.assertRaisesRegex(ValueError, "LOCATION_RISK_DRIFT"):
            validate(altered, self.recipes)

    def test_task_id_and_site_region_integrity_are_immutable(self) -> None:
        altered = copy.deepcopy(self.atlas)
        altered["levels"][38]["tasks"][0]["id"] = "JOB_001_1"
        with self.assertRaisesRegex(ValueError, "TASK_DRIFT"):
            validate(altered, self.recipes)
        altered = copy.deepcopy(self.atlas)
        altered["levels"][65]["region_id"] = "REG_01"
        with self.assertRaisesRegex(ValueError, "SITE_IDENTITY"):
            validate(altered, self.recipes)

    def test_stand_off_and_old_landmarks_are_actually_checked(self) -> None:
        location = self.atlas["locations"][0]
        points = positions(1, location["archetype"])
        _, anchor = choose(1, 1, points)
        self.assertGreaterEqual(clearance(anchor, points), STANDOFF)
        self.assertTrue(slot_clear(anchor, points))
        # Directly intersect a marker or any one original landmark envelope.
        self.assertFalse(slot_clear(points[0], points))
        for center, _ in PROTECTED:
            self.assertFalse(slot_clear(center, points))
        self.assertFalse(slot_clear((HALF / 2, HALF / 2), points))
        self.assertEqual(len(CELLS), 25)


if __name__ == "__main__":
    unittest.main()
