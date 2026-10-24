"""Unit tests for the executable bridge address specification."""

import unittest

from reference_model import Burst, RequestError, burst_addresses, is_legal_wstrb, legal_wstrb


class AddressModelTest(unittest.TestCase):
    def test_single_beat_incr(self):
        self.assertEqual(burst_addresses(0x100, 2, 0, Burst.INCR), [0x100])

    def test_fixed_keeps_address(self):
        self.assertEqual(burst_addresses(0x100, 2, 3, Burst.FIXED), [0x100] * 4)

    def test_increment_by_transfer_size(self):
        self.assertEqual(burst_addresses(0x04, 1, 3, Burst.INCR), [0x04, 0x06, 0x08, 0x0A])

    def test_wrap_four_words(self):
        self.assertEqual(burst_addresses(0x0C, 2, 3, Burst.WRAP), [0x0C, 0x00, 0x04, 0x08])

    def test_wrap_uses_current_address_after_first_wrap(self):
        self.assertEqual(burst_addresses(0x18, 2, 3, Burst.WRAP), [0x18, 0x1C, 0x10, 0x14])

    def test_byte_lane_masks(self):
        self.assertEqual(legal_wstrb(0x02, 0), 0b0100)
        self.assertEqual(legal_wstrb(0x02, 1), 0b1100)
        self.assertEqual(legal_wstrb(0x04, 2), 0b1111)

    def test_mask_validator(self):
        self.assertTrue(is_legal_wstrb(0x02, 1, 0b1100))
        self.assertFalse(is_legal_wstrb(0x02, 1, 0b0100))

    def test_reject_unaligned(self):
        with self.assertRaises(RequestError):
            burst_addresses(0x01, 1, 0, Burst.INCR)

    def test_reject_reserved_burst(self):
        with self.assertRaises(RequestError):
            burst_addresses(0x00, 2, 0, 0b11)

    def test_reject_bad_wrap_length(self):
        with self.assertRaises(RequestError):
            burst_addresses(0x00, 2, 2, Burst.WRAP)

    def test_reject_burst_larger_than_configuration(self):
        with self.assertRaises(RequestError):
            burst_addresses(0x00, 2, 8, Burst.INCR, max_burst_beats=8)

    def test_reject_increment_crossing_4kb(self):
        with self.assertRaises(RequestError):
            burst_addresses(0xFFC, 2, 1, Burst.INCR)
        self.assertEqual(burst_addresses(0xFF8, 2, 1, Burst.INCR), [0xFF8, 0xFFC])

    def test_fixed_at_page_end_is_not_increment(self):
        self.assertEqual(burst_addresses(0xFFC, 2, 3, Burst.FIXED), [0xFFC] * 4)

    def test_wrap_at_page_end_stays_in_wrap_block(self):
        self.assertEqual(burst_addresses(0xFFC, 2, 3, Burst.WRAP), [0xFFC, 0xFF0, 0xFF4, 0xFF8])

    def test_fixed_burst_never_exceeds_16(self):
        with self.assertRaises(RequestError):
            burst_addresses(0, 2, 16, Burst.FIXED, max_burst_beats=32)

    def test_reject_address_overflow(self):
        with self.assertRaises(RequestError):
            burst_addresses(0xFFFFFFFC, 2, 1, Burst.INCR)


if __name__ == "__main__":
    unittest.main(verbosity=2)
