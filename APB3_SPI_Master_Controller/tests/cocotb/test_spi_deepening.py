"""Public-pin regressions for active-divider atomicity and frame boundaries.

These tests intentionally do not add to the original 23 functional bins.
"""

import cocotb
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge
from cocotb.utils import get_sim_time

import test_apb3_spi as apb


async def reset(dut):
    await FallingEdge(dut.pclk)
    dut.presetn.value = 0
    dut.psel.value = 0
    dut.penable.value = 0
    dut.pwrite.value = 0
    dut.paddr.value = 0
    dut.pwdata.value = 0
    dut.spi_miso.value = 0
    for _ in range(3):
        await FallingEdge(dut.pclk)
    dut.presetn.value = 1
    await FallingEdge(dut.pclk)


async def check_frame_timing(dut, width, divider, cpol):
    """Observe only PCLK/SCLK/CS: each half-period and exact edge count."""
    expected_ns = (divider + 1) * 10
    started = False
    edges = 0
    last_level = cpol
    last_edge_ns = None
    for _ in range(2 * width * (divider + 1) + 100):
        await RisingEdge(dut.pclk)
        await ReadOnly()
        now = int(get_sim_time(unit="ns"))
        cs = int(dut.spi_cs_n.value)
        level = int(dut.spi_sclk.value)
        if not started:
            if cs:
                continue
            started = True
            last_edge_ns = now
            assert level == cpol, "START did not begin at configured CPOL"
            continue
        if level != last_level:
            assert now - last_edge_ns == expected_ns, (
                f"active divider changed: edge {edges + 1}, expected "
                f"{expected_ns} ns, observed {now - last_edge_ns} ns"
            )
            edges += 1
            last_edge_ns = now
            last_level = level
        assert now - last_edge_ns < expected_ns, (
            f"active divider changed: missing edge {edges + 1}; "
            f"expected after {expected_ns} ns (divider={divider})"
        )
        if cs:
            assert edges == 2 * width, f"expected {2 * width} edges, got {edges}"
            assert level == cpol, "final edge did not restore CPOL"
            return
    raise AssertionError("frame did not start or complete within its bound")


async def run_checked_frame(dut, *, mode, width, divider, lsb=False,
                            program_static=True):
    cpol, cpha = mode >> 1, mode & 1
    mask = (1 << width) - 1
    tx = 0x96A53CB5 & mask
    response = 0x693ACB4B & mask
    timing = cocotb.start_soon(check_frame_timing(dut, width, divider, cpol))
    slave = cocotb.start_soon(apb.spi_slave_frame(
        dut, cpol=cpol, cpha=cpha, width=width, lsb_first=lsb,
        response=response))
    await apb.start_frame(
        dut, tx_word=tx, cpol=cpol, cpha=cpha, width=width,
        lsb_first=lsb, continuous=False, divider=divider,
        program_static=program_static)
    await timing
    assert await slave == tx
    assert await apb.apb_read(dut, apb.RXDATA) == response
    assert (await apb.apb_read(dut, apb.STATUS)) & 1 == 0


@cocotb.test(timeout_time=200, timeout_unit="us")
@cocotb.parametrize(mode=[0, 1, 2, 3], change=["increase", "decrease"])
async def busy_clkdiv_write_keeps_active_frame(dut, mode, change):
    await reset(dut)
    old_divider, next_divider = (1, 7) if change == "increase" else (7, 0)
    cpol, cpha = mode >> 1, mode & 1
    timing = cocotb.start_soon(check_frame_timing(dut, 8, old_divider, cpol))
    slave = cocotb.start_soon(apb.spi_slave_frame(
        dut, cpol=cpol, cpha=cpha, width=8, lsb_first=False, response=0x69))
    await apb.start_frame(
        dut, tx_word=0xB5, cpol=cpol, cpha=cpha, width=8,
        lsb_first=False, continuous=False, divider=old_divider)
    # Start the software write after a public SCLK edge, while the frame is busy.
    if cpol == 0:
        await RisingEdge(dut.spi_sclk)
    else:
        await FallingEdge(dut.spi_sclk)
    await apb.apb_write(dut, apb.CLKDIV, next_divider)
    assert await apb.apb_read(dut, apb.CLKDIV) == next_divider
    await timing
    assert await slave == 0xB5
    assert await apb.apb_read(dut, apb.RXDATA) == 0x69
    # The software-visible write must take effect on the *next* START.
    await run_checked_frame(dut, mode=mode, width=8, divider=next_divider,
                            program_static=False)


@cocotb.test(timeout_time=200, timeout_unit="us")
@cocotb.parametrize(mode=[0, 1, 2, 3], width=[1, 32], lsb=[False, True])
async def frame_boundaries_at_divider_zero(dut, mode, width, lsb):
    await reset(dut)
    await run_checked_frame(dut, mode=mode, width=width, divider=0, lsb=lsb)
