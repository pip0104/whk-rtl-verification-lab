"""Public-pin regressions: phase timing, late illegality and AXI page limits."""
import cocotb
from pathlib import Path
from cocotb.triggers import RisingEdge, Timer

from bridge_bfm import BridgeTestbench, FunctionalCoverage, AXI_OKAY, AXI_DECERR, AXI_SLVERR


async def setup(dut):
    tb = BridgeTestbench(dut, FunctionalCoverage())
    tb.start()
    await tb.reset()
    return tb


@cocotb.test()
async def separate_address_and_data_phase(dut):
    """Early HRDATA sampling returns poison instead of the addressed word."""
    tb = await setup(dut)
    tb.ahb.memory[0x120] = 0x1234ABCD
    await tb.send_ar(ident=3, address=0x120, length=0, size=2, burst=1)
    await tb.get_r(ident=3, expected=[(0x1234ABCD, AXI_OKAY)])
    await tb.send_aw(ident=4, address=0x124, length=0, size=2, burst=1)
    await tb.send_w(data=0x87654321, strb=15, last=True)
    await tb.get_b(ident=4, response=AXI_OKAY)
    assert tb.ahb.read_word(0x124) == 0x87654321, "write data must belong to the accepted address"


@cocotb.test()
async def late_illegal_write_has_zero_side_effects(dut):
    """A bad second strobe/late WLAST must be found before the first AHB write."""
    tb = await setup(dut)
    for last_values, strobes in (([False, True], [15, 3]), ([False, False], [15, 15])):
        before = len(tb.ahb.beats)
        await tb.send_aw(ident=5, address=0x200, length=1, size=2, burst=1)
        await tb.send_w(data=0x11111111, strb=strobes[0], last=last_values[0])
        await tb.send_w(data=0x22222222, strb=strobes[1], last=last_values[1])
        await tb.get_b(ident=5, response=AXI_DECERR)
        assert len(tb.ahb.beats) == before, "late illegal W beat already caused an AHB side effect"
        assert tb.ahb.read_word(0x200) == 0


@cocotb.test()
async def page_boundary_and_two_cycle_error(dut):
    """Reject INCR crossing 4KB; permit FIXED/WRAP ending inside that page."""
    tb = await setup(dut)
    before = len(tb.ahb.beats)
    await tb.send_ar(ident=1, address=0xFFC, length=1, size=2, burst=1)
    await tb.get_r(ident=1, expected=[(0, AXI_DECERR), (0, AXI_DECERR)])
    assert len(tb.ahb.beats) == before, "cross-page INCR reached AHB"
    await tb.send_aw(ident=2, address=0xFFC, length=1, size=2, burst=1)
    await tb.send_w(data=0x11111111, strb=15, last=False)
    await tb.send_w(data=0x22222222, strb=15, last=True)
    await tb.get_b(ident=2, response=AXI_DECERR)
    assert len(tb.ahb.beats) == before
    tb.ahb.memory[0xFFC] = 0x89ABCDEF
    tb.ahb.memory[0xFF8] = 0x10203040
    for burst, expected in ((0, [0x89ABCDEF, 0x89ABCDEF]), (2, [0x89ABCDEF, 0x10203040])):
        await tb.send_ar(ident=3, address=0xFFC, length=1, size=2, burst=burst)
        await tb.get_r(ident=3, expected=[(value, AXI_OKAY) for value in expected])
    tb.ahb.schedule(waits=[2], errors=[True])
    await tb.send_ar(ident=4, address=0x300, length=1, size=2, burst=1)
    await tb.get_r(ident=4, expected=[(0, AXI_SLVERR), (0, AXI_SLVERR)])
    assert tb.ahb.error_responses == [(1, 0), (1, 1)], "ERROR must hold HRESP high across low/high HREADY"
    assert not tb.ahb.beats[-2].error and tb.ahb.beats[-1].error


@cocotb.test()
async def required_coverage_bins_fail_closed(dut):
    """Empty/partial coverage must fail even when the simulator ran normally."""
    path = Path(__file__).resolve().parents[2] / "results" / "deepening" / "coverage_gate_negative.json"
    try:
        FunctionalCoverage().write_report(path)
    except AssertionError as error:
        assert "direction:READ" in str(error)
    else:
        raise AssertionError("Missing coverage bins incorrectly reported success")
