import copy
import importlib.util
import json
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "audit_replayxi_tripo_sources.py"
spec = importlib.util.spec_from_file_location("tripo_audit", SCRIPT)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class TripoSourceAuditTests(unittest.TestCase):
    def setUp(self):
        self.ledger = json.loads(audit.LEDGER.read_text())

    def test_current_ledger_reserves_thirty_percent(self):
        report = audit.audit_budget(self.ledger)
        self.assertGreaterEqual(report["lastObservedBalance"], report["minimumReserve"])

    def test_floor_rounding_does_not_spend_reserve(self):
        self.assertEqual(self.ledger["minimumRemainingBalance"], 944)
        changed = copy.deepcopy(self.ledger)
        changed["maximumCumulativeSpend"] = 2202
        with self.assertRaises(ValueError):
            audit.audit_budget(changed)

    def test_shared_account_other_spend_reduces_headroom(self):
        self.ledger["latestObservedBalance"] = 1000
        self.assertEqual(audit.audit_budget(self.ledger)["additionalSpendCeilingAtObservation"], 56)
        self.ledger["latestObservedBalance"] = 943
        with self.assertRaises(ValueError):
            audit.audit_budget(self.ledger)

    def test_unrecorded_cost_fails(self):
        self.ledger["verifiedCreditsSpent"] += 1
        with self.assertRaises(ValueError):
            audit.audit_budget(self.ledger)

    def test_invalid_credit_values_fail(self):
        for invalid in (-1, 20.5, True, "20"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                audit.count(invalid)

    def test_source_glbs_have_valid_bounded_headers(self):
        for job in self.ledger["jobs"]:
            if "export" in job:
                path = audit.LEDGER.parent / job["export"]
                self.assertTrue(audit.glb_document(path.read_bytes())["meshes"])

    def test_truncated_glb_fails(self):
        for payload in (b"", b"glTF", bytes(28)):
            with self.subTest(length=len(payload)), self.assertRaises(ValueError):
                audit.glb_document(payload)


if __name__ == "__main__":
    unittest.main()
