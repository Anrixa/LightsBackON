"""RB02 location format (tools/lbo_location.py). The same cases run in tests/unit/test_RB02_location_format.gd."""
from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "reference"))

import lbo_challenge  # noqa: E402
import lbo_location as L  # noqa: E402

DATA = ROOT / "tests" / "data" / "locations"
C01 = ROOT / "content" / "contracts" / "c01_alder_street"


def codes(diags: list[dict]) -> list[str]:
    return sorted({d["code"] for d in diags})


class RB02LocationFormat(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.alder = L.load(L.LOCATIONS / "alder_street")
        cls.cases = json.loads((DATA / "cases.json").read_text(encoding="utf-8"))
        cls.challenge = json.loads((DATA / "alder_c01_challenge.json").read_text(encoding="utf-8"))
        cls.kit, cls.dims = L.kit_ids(), L.dimensions()

    def test_RB02_every_location_and_pinned_contract_validates(self) -> None:
        self.assertEqual(L.check_all(), [])
        self.assertIn("ALDER_STREET", L.all_locations())

    def test_RB02_location_parity_cases(self) -> None:
        self.assertGreaterEqual(len(self.cases["location_cases"]), 20)
        for case in self.cases["location_cases"]:
            with self.subTest(case["name"]):
                got = L.validate(L.apply_patch(self.alder, case["ops"]), self.kit, self.dims)
                self.assertEqual(codes(got), case["codes"], got)

    def test_RB02_challenge_parity_cases(self) -> None:
        for case in self.cases["challenge_cases"]:
            with self.subTest(case["name"]):
                got = L.check_challenge(self.alder, L.apply_patch({"c": self.challenge}, [
                    {**op, "path": ["c"] + op["path"]} for op in case["ops"]])["c"])
                self.assertEqual(codes(got), case["codes"], got)

    def test_RB02_c01_fits_alder_street(self) -> None:
        self.assertEqual(L.check_contract(self.alder, C01), [])

    def test_RB02_a_contract_on_the_wrong_street_is_refused(self) -> None:
        got = L.check_contract(self.alder, ROOT / "content" / "contracts" / "c05_canal_pump_access")
        self.assertIn("CONTRACT_MISMATCH", codes(got))

    def test_RB02_challenge_fixture_is_c01_on_alder_and_loads_in_rb03(self) -> None:
        rules = json.loads((ROOT / "content" / "challenges" / "rules.json").read_text(encoding="utf-8"))
        want = lbo_challenge.from_contract(C01, rules)
        want["location_id"], want["id"] = "ALDER_STREET", "ALDER_STREET_STORY_C01"
        self.assertEqual(self.challenge, want, "regenerate tests/data/locations/alder_c01_challenge.json")
        self.assertEqual(lbo_challenge.validate(self.challenge), [])

    def test_RB02_merged_look_and_dressing_keep_the_ds08_shape(self) -> None:
        look, dress = L.merged_look(self.alder), L.merged_dressing(self.alder)
        self.assertEqual(look["buildings"], self.alder["look"]["palette"])
        for b in self.alder["layout"]["buildings"]:
            self.assertIn(b["id"], look["buildings"], "every building has a palette")
        self.assertEqual(len(dress["lamps"]), len(self.alder["look"]["lamps"]))
        self.assertNotIn("buildings", json.loads((ROOT / "content/world/look_stormglass.json").read_text(encoding="utf-8")),
                         "the palette lives with the location")

    def test_RB02_presentation_files_are_listed_and_rules_files_are_not(self) -> None:
        compat = json.loads((ROOT / "content" / "save_compat.json").read_text(encoding="utf-8"))
        listed = {e["path"] for e in compat["presentation_only"]}
        self.assertIn("content/locations/alder_street/dressing.json", listed)
        self.assertIn("content/locations/alder_street/look.json", listed)
        self.assertNotIn("content/locations/alder_street/layout.json", listed)
        self.assertNotIn("content/locations/alder_street/location.json", listed)

    def test_RB02_cli_exits_zero(self) -> None:
        out = subprocess.run([sys.executable, str(ROOT / "tools" / "lbo_location.py")], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)


if __name__ == "__main__":
    unittest.main()
