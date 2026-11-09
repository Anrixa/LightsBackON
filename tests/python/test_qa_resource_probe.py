"""QA51 parser tests: prove that diagnostic warnings remain visible as counts."""
import unittest

from tools.qa_resource_probe import CASES, isolated_env, parse_log, regression_violations


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
        self.assertEqual(regression_violations("v07_unit", leaked), [],
                         "unqualified renderer/font warnings remain visible, not falsely gated")

    def test_qa52_isolates_existing_test_families(self):
        self.assertEqual(CASES["v07_unit"], ["--filter=V07_ui"])
        self.assertEqual(CASES["v07_tablet_layout"], ["--filter=V07_tablet_fits"])
        self.assertEqual(CASES["v07_live"], ["--filter=V07_live"])
        self.assertEqual(CASES["a04_live"], ["--filter=A04_live"])

    def test_qa52_aggregates_verbose_leaked_object_owners(self):
        log = """Leaked instance: GDScript:9223372077187204606 - Reference count: 8
Leaked instance: StyleBoxFlat:9223372061567616381 - Reference count: 2
Leaked instance: GDScript:9223372066231682559 - Reference count: 7
tests: 2 passed, 0 failed, 10 assertions
"""
        parsed = parse_log(log)
        self.assertEqual(parsed["leaked_object_classes"], {
            "GDScript": 2, "StyleBoxFlat": 1
        })
        self.assertEqual(parsed["passed"], 2)

    def test_qa52_live_host_lifetime_rejects_refcount_regressions(self):
        clean = {"CanvasItem": 0, "ObjectDB": 0, "DummyTexture": 0}
        for case in ("offline_ownership", "power_scene", "v07_live", "a04_live"):
            self.assertEqual(regression_violations(case, clean), [])
            escaped = {**clean, "ObjectDB": 1}
            self.assertEqual(
                regression_violations(case, escaped),
                ["ObjectDB=1 exceeds 0"],
                f"{case} must catch a leaked host or outbox graph",
            )
        # The separate text-renderer and menu lifecycle investigation remains
        # visible without asserting that remaining RID warnings are resolved.
        self.assertEqual(regression_violations("v07_unit", escaped), [])

    def test_qa53_isolated_font_resources_and_menu_regression_ceilings(self):
        zero = dict.fromkeys(("CanvasItem", "ObjectDB", "ShapedText", "FontRID"), 0)
        for case in ("font_theme", "plain_label_lifetime", "project_label_lifetime",
                     "plain_shaped_labels", "project_shaped_labels", "dialog_lifetime"):
            self.assertEqual(regression_violations(case, zero), [], case)
            self.assertEqual(regression_violations(case, {**zero, "ShapedText": 1}),
                             ["ShapedText=1 exceeds 0"], case)
        # QA55 removed the orphaned production StartButton. The previously
        # observed menu/FontRID exit warnings now all have measured zero caps.
        menu = {"CanvasItem": 0, "ObjectDB": 0, "ShapedText": 0, "FontRID": 0,
                "DummyTexture": 0}
        self.assertEqual(regression_violations("menu_reflow", menu), [])
        self.assertEqual(regression_violations(
            "menu_reflow", {**menu, "CanvasItem": 1}), ["CanvasItem=1 exceeds 0"])
        self.assertEqual(CASES["menu_reflow_frame_settled"],
                         ["--filter=DS01", "--settle-frames=30"])
        self.assertEqual(CASES["font_menu_frame_settled"],
                         ["--dir=res://tests/diagnostics", "--filter=QA53_multiple", "--settle-frames=30"])

    def test_qa54_menu_component_cases_are_independent(self):
        # Stage-by-stage fixtures must run in separate engine processes.
        stages = {
            "qa54_structure": "QA54_structure_only",
            "qa54_text": "QA54_structured_text",
            "qa54_buttons": "QA54_buttons",
            "qa54_dialog": "QA54_dialog",
            "qa54_reflow": "QA54_reflow",
            "qa54_signals": "QA54_signals_and_focus",
            "qa54_packed_unentered": "QA54_packed_scene_not_entered",
            "qa54_packed_scriptless": "QA54_packed_scene_without_script",
            "qa54_real_no_reflow": "QA54_actual_menu_without_reflow",
        }
        for case, method in stages.items():
            self.assertEqual(CASES[case],
                             ["--dir=res://tests/diagnostics", f"--filter={method}"])
            observed = {"CanvasItem": 0, "ObjectDB": 0,
                        "ShapedText": 0, "FontRID": 0, "DummyTexture": 0}
            self.assertEqual(regression_violations(case, observed), [], case)
            self.assertEqual(regression_violations(
                case, {**observed, "ObjectDB": observed["ObjectDB"] + 1}),
                [f"ObjectDB={observed['ObjectDB'] + 1} exceeds {observed['ObjectDB']}"],
                f"{case} must detect growth above the cross-OS measured limit")

    def test_qa55_recovered_menu_is_zero_warning_gated(self):
        # All of these formerly warned in QA53/QA54: a new orphaned
        # never-parented Button must fail on both hosted OSes.
        recovered = (
            "font_menu_single", "font_menu_repeated", "font_ui_lifetime",
            "font_menu_frame_settled", "menu_reflow", "menu_reflow_frame_settled",
            "menu_geometry_only", "menu_focus_only", "v01_offline",
            "qa54_real_no_reflow", "qa55_menu_lifetime",
        )
        kinds = ("CanvasItem", "ObjectDB", "ShapedText", "FontRID", "DummyTexture")
        zero = dict.fromkeys(kinds, 0)
        self.assertEqual(CASES["qa55_menu_lifetime"], ["--filter=QA55"])
        for case in recovered:
            self.assertEqual(regression_violations(case, zero), [], case)
            for kind in kinds:
                self.assertEqual(regression_violations(case, {**zero, kind: 1}),
                                 [f"{kind}=1 exceeds 0"], (case, kind))

    def test_script_error_cannot_be_hidden_by_passing_summary(self):
        parsed = parse_log("SCRIPT ERROR: Invalid set index\ntests: 5 passed, 0 failed, 7 assertions")
        self.assertTrue(parsed["script_error"])

    def test_SAVE22_probe_runs_point_godot_user_dir_at_the_temp_root(self):
        env = isolated_env("build/some_root", base={"APPDATA": "C:/Users/me/AppData/Roaming", "KEEP": "1"})
        root = env["LBO_TEST_USER_ROOT"]
        self.assertTrue(root.endswith("build/some_root"))
        self.assertNotIn("\\", root)
        self.assertEqual(env["APPDATA"], root)
        self.assertEqual(env["XDG_DATA_HOME"], root)
        self.assertEqual(env["KEEP"], "1")


if __name__ == "__main__":
    unittest.main()
