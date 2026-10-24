"""Guard against a simulator exit code hiding failed, stale or empty tests."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("portfolio_verify", Path(__file__).parents[1] / "scripts" / "verify.py")
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class EvidenceGateTests(unittest.TestCase):
    def read(self, xml):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "results.xml"
            path.write_text(xml, encoding="utf-8")
            return verify.check_junit(path)

    def test_real_passing_case_is_counted(self):
        result = self.read('<testsuites><testsuite tests="1" failures="0" errors="0"><testcase name="rtl"/></testsuite></testsuites>')
        self.assertEqual(result["tests"], 1)

    def test_child_failure_rejected_even_without_suite_counters(self):
        with self.assertRaises(RuntimeError):
            self.read('<testsuites><testsuite><testcase name="rtl"><failure message="wrong data"/></testcase></testsuite></testsuites>')

    def test_suite_error_rejected_even_without_child_failure(self):
        with self.assertRaises(RuntimeError):
            self.read('<testsuite tests="1" errors="1"><testcase name="rtl"/></testsuite>')

    def test_empty_and_all_skipped_are_not_a_pass(self):
        for xml in ('<testsuites/>', '<testsuite><testcase name="rtl"><skipped/></testcase></testsuite>'):
            with self.subTest(xml=xml), self.assertRaises(RuntimeError):
                self.read(xml)

    def test_both_project_coverage_schemas_are_accepted(self):
        verify.check_coverage({"required_bins": 23, "hit_bins": 23})
        verify.check_coverage({"required_bins": 36, "covered_required_bins": 36, "missing_required_bins": []})

    def test_incomplete_or_unreported_coverage_is_rejected(self):
        for report in ({"required_bins": 36, "covered_required_bins": 35},
                       {"required_bins": 23},
                       {"required_bins": 23, "hit_bins": 23, "missing_required_bins": ["error"]}):
            with self.subTest(report=report), self.assertRaises(RuntimeError):
                verify.check_coverage(report)


if __name__ == "__main__":
    unittest.main()
