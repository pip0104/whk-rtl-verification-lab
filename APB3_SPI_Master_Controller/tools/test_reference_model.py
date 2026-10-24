"""Unit tests for the SPI transaction oracle; run before RTL regressions."""

import unittest

from reference_model import (
    SpiConfig,
    assemble_bits,
    edge_plan,
    expected_half_period_pclks,
    transfer,
    wire_bits,
)


class ReferenceModelTests(unittest.TestCase):
    def test_msb_first_wire_order(self):
        self.assertEqual(wire_bits(0xA5, 8, False), [1, 0, 1, 0, 0, 1, 0, 1])

    def test_lsb_first_wire_order(self):
        self.assertEqual(wire_bits(0xA5, 8, True), [1, 0, 1, 0, 0, 1, 0, 1])

    def test_non_palindromic_lsb_first_order(self):
        self.assertEqual(wire_bits(0x96, 8, True), [0, 1, 1, 0, 1, 0, 0, 1])

    def test_assemble_msb_first(self):
        self.assertEqual(assemble_bits([1, 0, 1, 0, 0, 1, 1, 0], 8, False), 0xA6)

    def test_assemble_lsb_first(self):
        self.assertEqual(assemble_bits([1, 1, 0, 1, 0, 0, 1, 0], 8, True), 0x4B)

    def test_all_modes_have_two_edges_per_bit(self):
        for cpol in (0, 1):
            for cpha in (0, 1):
                plan = edge_plan(SpiConfig(cpol, cpha, 0, 13))
                self.assertEqual(len(plan), 26)
                self.assertEqual(plan[0][0], "leading")
                self.assertEqual(plan[-1][0], "trailing")

    def test_cpha_zero_samples_leading(self):
        plan = edge_plan(SpiConfig(1, 0, 0, 3))
        self.assertEqual([sample for _, _, sample in plan], [True, False] * 3)

    def test_cpha_one_samples_trailing(self):
        plan = edge_plan(SpiConfig(0, 1, 0, 3))
        self.assertEqual([sample for _, _, sample in plan], [False, True] * 3)

    def test_cpol_returns_to_idle(self):
        for cpol in (0, 1):
            self.assertEqual(edge_plan(SpiConfig(cpol, 0, 0, 8))[-1][1], cpol)

    def test_divider_encoding(self):
        self.assertEqual(expected_half_period_pclks(SpiConfig(0, 0, 0, 8)), 1)
        self.assertEqual(expected_half_period_pclks(SpiConfig(0, 0, 7, 8)), 8)

    def test_transfer_reconstructs_response(self):
        config = SpiConfig(1, 1, 3, 16, True)
        mosi, received = transfer(0x0000_B4D2, 0x0000_3CA5, config)
        self.assertEqual(mosi, wire_bits(0xB4D2, 16, True))
        self.assertEqual(received, 0x3CA5)

    def test_invalid_width_rejected(self):
        with self.assertRaises(ValueError):
            SpiConfig(0, 0, 0, 33).validate()


if __name__ == "__main__":
    unittest.main(verbosity=2)
