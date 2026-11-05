"""QA51 parser tests: prove that diagnostic warnings remain visible as counts."""
import unittest

from tools.qa_resource_probe import parse_log, regression_violations


class ResourceProbeTests(unittest.TestCase):
    def test_no_warnings_counts_zero(self):
        result = parse_log("tests: 0 passed, 0 failed, 0 assertions\n")
        self.assertEqual(result["counts"], dict.fromkeys(
            ("CanvasItem", "ObjectDB", "DummyTexture", "ShapedText", "FontRID"), 0
        ))
        self.assertEqual(result["passed"], 0)
        self.assertFalse(result["script_error"])

    def test_distinguishes_rid_families_and_failures(self):
        log = """tests: 263 passed, 0 failed, 8243 assertions
WARNING: 859 RIDs of type "CanvasItem" were leaked.
WARNING: 2431 ObjectDB instances were leaked at exit (run with `--verbose` for details).
ERROR: 11 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.
ERROR: 8 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit.
ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.
"""
        parsed = parse_log(log)
        self.assertEqual(parsed["counts"], {
            "CanvasItem": 859, "ObjectDB": 2431, "DummyTexture": 11,
            "ShapedText": 8, "FontRID": 1,
        })
        self.assertEqual((parsed["passed"], parsed["failed"], parsed["assertions"]),
                         (263, 0, 8243))
        self.assertEqual(len(parsed["warning_excerpt"]), 5)

    def test_detached_tablet_map_leak_fails_bounded_gate(self):
        clean = {"CanvasItem": 0, "ObjectDB": 58, "DummyTexture": 0}
        self.assertEqual(regression_violations("tablet_scene", clean), [])
        leaked = {"CanvasItem": 340, "ObjectDB": 814, "DummyTexture": 4}
        self.assertEqual(len(regression_violations("tablet_objectives_only", leaked)), 2)
        # Residual ObjectDB warnings stay visible but are not silently declared a fix.
        self.assertEqual(regression_violations("power_scene", leaked), [])

    def test_script_error_cannot_be_hidden_by_passing_summary(self):
        parsed = parse_log("SCRIPT ERROR: Invalid set index\ntests: 5 passed, 0 failed, 7 assertions")
        self.assertTrue(parsed["script_error"])


if __name__ == "__main__":
    unittest.main()
