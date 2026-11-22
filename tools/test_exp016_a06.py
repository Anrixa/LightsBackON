"""EXP016 A06 source mutation test."""
import copy
import unittest
from validate_exp016_a06 import qualify,read

class SourceFaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a=read("atlas.json");cls.f=read("fault_diagnostics.json")
        cls.e=read("bespoke_encounters.json");cls.b=read("exp016_fault_layers_a06.json")

    def test_source_pins(self):
        self.assertEqual(qualify(self.a,self.f,self.e,self.b)["levels"],200)

    def test_conflicting_secondary_source_rejected(self):
        b=copy.deepcopy(self.b)
        b["entries"][24]["secondary_fault_class"]="environmental_forged"
        with self.assertRaisesRegex(ValueError,"SOURCE_DRIFT"):qualify(self.a,self.f,self.e,b)
