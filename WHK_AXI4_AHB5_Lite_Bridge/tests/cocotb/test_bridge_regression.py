"""End-to-end, seed-stable functional regression for the AXI4/AHB5-Lite bridge."""

from __future__ import annotations

from pathlib import Path
import random

import cocotb
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge, Timer

from bridge_bfm import (
    AXI_DECERR,
    AXI_OKAY,
    AXI_SLVERR,
    BridgeTestbench,
    Burst,
    FunctionalCoverage,
    lane_mask,
)


async def check_write(
    tb: BridgeTestbench,
    *,
    ident: int,
    address: int,
    size: int,
    burst: Burst,
    data: list[int],
    response: int = AXI_OKAY,
    waits: list[int] | None = None,
    errors: list[bool] | None = None,
    wstrbs: list[int] | None = None,
    last_values: list[bool] | None = None,
    b_stall_cycles: int = 0,
) -> list[int]:
    """Drive one write, compare AHB conversion, then update the scoreboard."""

    if waits is not None or errors is not None:
        tb.ahb.schedule(waits=waits or [], errors=errors or [])
    start = len(tb.ahb.beats)
    addresses = await tb.write_burst(
        ident=ident,
        address=address,
        size=size,
        burst=burst,
        data=data,
        wstrbs=wstrbs,
        last_values=last_values,
        response=response,
        b_stall_cycles=b_stall_cycles,
    )
    if response != AXI_DECERR:
        observed = tb.check_ahb_beats(
            start_index=start,
            addresses=addresses,
            write=True,
            size=size,
            burst=burst,
            data=data,
            errors=errors,
        )
        # An ERROR transfer itself does not update memory.  Earlier OKAY beats
        # did complete and must remain visible, exactly as the spec requires.
        for index, item in enumerate(data[:len(observed)]):
            if not observed[index].error:
                tb.expected_write(addresses[index], item, size)
    else:
        assert len(tb.ahb.beats) == start, "DECERR write must not reach AHB"
    tb.check_memory()
    return addresses


async def check_read(
    tb: BridgeTestbench,
    *,
    ident: int,
    address: int,
    size: int,
    burst: Burst,
    beats: int,
    response: int = AXI_OKAY,
    waits: list[int] | None = None,
    errors: list[bool] | None = None,
    r_stall_cycles: int = 0,
) -> list[int]:
    """Drive one read and use the independent memory scoreboard for R data."""

    if waits is not None or errors is not None:
        tb.ahb.schedule(waits=waits or [], errors=errors or [])
    addresses = __import__("reference_model").burst_addresses(
        address, size, beats - 1, burst, max_burst_beats=16
    )
    error_index = next((index for index, value in enumerate(errors or []) if value), None)
    expected = []
    for index, item_address in enumerate(addresses):
        if response == AXI_DECERR or (error_index is not None and index >= error_index):
            expected.append((0, AXI_DECERR if response == AXI_DECERR else AXI_SLVERR))
        else:
            expected.append((tb.expected_read(item_address, size), AXI_OKAY))
    start = len(tb.ahb.beats)
    result_addresses = await tb.read_burst(
        ident=ident,
        address=address,
        size=size,
        burst=burst,
        expected=expected,
        r_stall_cycles=r_stall_cycles,
    )
    if response == AXI_DECERR:
        assert len(tb.ahb.beats) == start, "DECERR read must not reach AHB"
    else:
        tb.check_ahb_beats(
            start_index=start,
            addresses=result_addresses,
            write=False,
            size=size,
            burst=burst,
            errors=errors,
        )
    return result_addresses


async def case_single_and_narrow(tb: BridgeTestbench) -> None:
    await check_write(
        tb, ident=1, address=0x20, size=2, burst=Burst.INCR,
        data=[0xDEAD_BEEF], b_stall_cycles=2,
    )
    await check_read(
        tb, ident=2, address=0x20, size=2, burst=Burst.INCR,
        beats=1, r_stall_cycles=2,
    )

    # All 1-byte address lanes and both legal 2-byte lanes are exercised.
    for lane in range(4):
        address = 0x40 + lane
        await check_write(
            tb, ident=3, address=address, size=0, burst=Burst.INCR,
            data=[(0xA0 + lane) << (lane * 8)],
        )
        await check_read(tb, ident=4, address=address, size=0, burst=Burst.INCR, beats=1)
    for lane in (0, 2):
        address = 0x50 + lane
        await check_write(
            tb, ident=5, address=address, size=1, burst=Burst.INCR,
            data=[(0xB000 + lane) << (lane * 8)],
        )
        await check_read(tb, ident=6, address=address, size=1, burst=Burst.INCR, beats=1)


async def case_burst_conversion(tb: BridgeTestbench) -> None:
    # INCR2 is retained as a distinct boundary case from the longer INCR4/16
    # bursts below.
    await check_write(
        tb, ident=6, address=0x0E0, size=2, burst=Burst.INCR,
        data=[0x1010_0000, 0x1010_0001],
    )
    await check_read(tb, ident=7, address=0x0E0, size=2, burst=Burst.INCR, beats=2)

    # INCR4; then use the read path to prove the stored data and RLAST.
    incr_data = [0x1111_0000 + index for index in range(4)]
    await check_write(tb, ident=8, address=0x100, size=2, burst=Burst.INCR, data=incr_data)
    await check_read(tb, ident=9, address=0x100, size=2, burst=Burst.INCR, beats=4)

    # FIXED does not map to a sequential AHB burst.  The final write survives.
    fixed_data = [0x2222_0000 + index for index in range(4)]
    await check_write(tb, ident=10, address=0x140, size=2, burst=Burst.FIXED, data=fixed_data)
    await check_read(tb, ident=11, address=0x140, size=2, burst=Burst.FIXED, beats=4)

    # Starting at the final word of a WRAP4 block proves address wrap-around.
    wrap_data = [0x3333_0000 + index for index in range(4)]
    await check_write(tb, ident=12, address=0x16C, size=2, burst=Burst.WRAP, data=wrap_data)
    await check_read(tb, ident=13, address=0x16C, size=2, burst=Burst.WRAP, beats=4)

    # Explicit two-beat WRAP is the special SINGLE/NONSEQ mapping.
    await check_write(
        tb, ident=14, address=0x188, size=2, burst=Burst.WRAP,
        data=[0x4444_0000, 0x4444_0001],
    )
    await check_read(tb, ident=15, address=0x188, size=2, burst=Burst.WRAP, beats=2)

    # The long WRAP encodings have distinct AHB HBURST values and therefore
    # each gets a directed write/read check, not just random exposure.
    wrap8_data = [0x4555_0000 + index for index in range(8)]
    await check_write(tb, ident=0, address=0x1DC, size=2, burst=Burst.WRAP, data=wrap8_data)
    await check_read(tb, ident=1, address=0x1DC, size=2, burst=Burst.WRAP, beats=8)
    wrap16_data = [0x4666_0000 + index for index in range(16)]
    await check_write(tb, ident=2, address=0x3FC, size=2, burst=Burst.WRAP, data=wrap16_data)
    await check_read(tb, ident=3, address=0x3FC, size=2, burst=Burst.WRAP, beats=16)

    # Longest configured burst: covers INCR16 and 16-beat accounting.
    long_data = [0x5000_0000 + index for index in range(16)]
    await check_write(tb, ident=4, address=0x200, size=2, burst=Burst.INCR, data=long_data)
    await check_read(tb, ident=5, address=0x200, size=2, burst=Burst.INCR, beats=16)


async def case_w_before_aw(tb: BridgeTestbench) -> None:
    # AXI permits write data to arrive before its write address.  No command is
    # present yet, so no AHB beat may be emitted before the AW handshake.
    start = len(tb.ahb.beats)
    await tb.send_w(data=0x0BAD_F00D, strb=0b1111, last=True)
    for _ in range(3):
        await RisingEdge(tb.dut.clk)
    assert len(tb.ahb.beats) == start, "W without AW incorrectly reached AHB"
    await tb.send_aw(ident=1, address=0x280, length=0, size=2, burst=int(Burst.INCR))
    await tb.get_b(ident=1, response=AXI_OKAY)
    addresses = [0x280]
    tb.check_ahb_beats(start_index=start, addresses=addresses, write=True, size=2, burst=Burst.INCR, data=[0x0BAD_F00D])
    tb.expected_write(0x280, 0x0BAD_F00D, 2)
    tb.coverage.sample_request(direction="WRITE", burst=Burst.INCR, size=2, beats=1, address=0x280, response=AXI_OKAY)
    tb.check_memory()


async def case_strict_command_ordering(tb: BridgeTestbench) -> None:
    # The single command FIFO deliberately does not let a later AR overtake a
    # head AW that is still waiting for its W data.  This is a key, explicit
    # v0.1 ordering choice rather than an accidental implementation detail.
    start = len(tb.ahb.beats)
    await tb.send_aw(ident=2, address=0x290, length=0, size=2, burst=int(Burst.INCR))
    await tb.send_ar(ident=3, address=0x290, length=0, size=2, burst=int(Burst.INCR))
    for _ in range(4):
        await RisingEdge(tb.dut.clk)
    assert len(tb.ahb.beats) == start, "later AR overtook head write with missing W data"
    await tb.send_w(data=0xCAFE_BABE, strb=0b1111, last=True)
    await tb.get_b(ident=2, response=AXI_OKAY)
    await tb.get_r(ident=3, expected=[(0xCAFE_BABE, AXI_OKAY)])
    observed = tb.ahb.beats[start:]
    assert len(observed) == 2 and observed[0].write and not observed[1].write, "write/read execution order mismatch"
    tb.expected_write(0x290, 0xCAFE_BABE, 2)
    tb.coverage.sample_request(direction="WRITE", burst=Burst.INCR, size=2, beats=1, address=0x290, response=AXI_OKAY)
    tb.coverage.sample_request(direction="READ", burst=Burst.INCR, size=2, beats=1, address=0x290, response=AXI_OKAY)
    for beat in observed:
        tb.coverage.sample_ahb(beat)
    tb.check_memory()


async def case_wait_states_and_axi_backpressure(tb: BridgeTestbench) -> None:
    # HREADY waits of 1 and 4+ cycles, plus B/R source-side backpressure.
    await check_write(
        tb, ident=2, address=0x2A0, size=2, burst=Burst.INCR,
        data=[0xABCD_0001], waits=[1], errors=[False], b_stall_cycles=3,
    )
    await check_read(
        tb, ident=3, address=0x2A0, size=2, burst=Burst.INCR,
        beats=1, waits=[4], errors=[False], r_stall_cycles=3,
    )


async def case_illegal_requests(tb: BridgeTestbench) -> None:
    # Reserved AxBURST is rejected as a read DECERR without an AHB transfer.
    start = len(tb.ahb.beats)
    await tb.send_ar(ident=4, address=0x2C0, length=0, size=2, burst=0b11)
    await tb.get_r(ident=4, expected=[(0, AXI_DECERR)])
    assert len(tb.ahb.beats) == start, "reserved burst read reached AHB"
    tb.coverage.mark("response", "DECERR")
    tb.coverage.mark("direction", "READ")
    tb.coverage.mark("burst", "RESERVED")

    # Alignment and transfer-size violations are separate descriptor checks.
    for ident, address, size in ((13, 0x2C1, 2), (14, 0x2C0, 3)):
        start = len(tb.ahb.beats)
        await tb.send_ar(ident=ident, address=address, length=0, size=size, burst=int(Burst.INCR))
        await tb.get_r(ident=ident, expected=[(0, AXI_DECERR)])
        assert len(tb.ahb.beats) == start, "illegal read reached AHB"
        tb.coverage.mark("response", "DECERR")
        tb.coverage.mark("direction", "READ")

    # Wrong WSTRB and early WLAST both reject the whole write before AHB.
    await check_write(
        tb, ident=5, address=0x2D0, size=2, burst=Burst.INCR,
        data=[0xAAAA_0001], wstrbs=[0b0011], response=AXI_DECERR,
    )
    await check_write(
        tb, ident=6, address=0x2E0, size=2, burst=Burst.INCR,
        data=[0xAAAA_0002, 0xAAAA_0003],
        last_values=[True, False], response=AXI_DECERR,
    )

    # A 17-beat write exceeds the configured 16-entry FIFO.  It must be
    # accepted, streamed through the reject-and-drain path, return DECERR and
    # never deadlock while waiting for data that cannot all fit at once.
    start = len(tb.ahb.beats)
    await tb.send_aw(ident=7, address=0x2F0, length=16, size=2, burst=int(Burst.INCR))
    for index in range(17):
        await tb.send_w(data=0xAAAA_1000 + index, strb=0b1111, last=index == 16)
    await tb.get_b(ident=7, response=AXI_DECERR)
    assert len(tb.ahb.beats) == start, "oversized DECERR write reached AHB"
    tb.coverage.mark("response", "DECERR")
    tb.coverage.mark("direction", "WRITE")


async def case_ahb_errors(tb: BridgeTestbench) -> None:
    # Write ERROR on the middle beat: first beat remains committed, all later
    # W beats are drained, and exactly one SLVERR B is returned.
    await check_write(
        tb, ident=7, address=0x300, size=2, burst=Burst.INCR,
        data=[0x6000_0000 + index for index in range(4)],
        response=AXI_SLVERR, waits=[0, 2], errors=[False, True],
    )
    tb.coverage.mark("error_beat", "middle")

    # A read error on the first beat must return every R beat, all SLVERR, and
    # must not issue later AHB accesses.
    await check_read(
        tb, ident=8, address=0x100, size=2, burst=Burst.INCR,
        beats=4, waits=[0], errors=[True],
    )
    tb.coverage.mark("error_beat", "first")

    # Last-beat ERROR covers the other boundary and preserves earlier writes.
    await check_write(
        tb, ident=9, address=0x340, size=2, burst=Burst.INCR,
        data=[0x7000_0000 + index for index in range(4)],
        response=AXI_SLVERR, waits=[0, 0, 0, 0], errors=[False, False, False, True],
    )
    tb.coverage.mark("error_beat", "last")


async def case_fifo_full_and_recovery(tb: BridgeTestbench) -> None:
    # Fill the 16-entry W FIFO before any AW arrives.  The 17th W must be
    # backpressured; then the queued data are consumed in AW order.
    for index in range(16):
        await tb.send_w(data=0x8000_0000 + index, strb=0b1111, last=True)
    # READY itself is the backpressure signal.  Do not intentionally violate
    # AXI by asserting VALID and then withdrawing it before a handshake.
    for _ in range(3):
        await RisingEdge(tb.dut.clk)
        await ReadOnly()
        assert not int(tb.dut.s_wready.value), "WREADY stayed high on full FIFO"
    tb.coverage.mark("fifo_stress", "full_backpressure")
    tb.coverage.mark("fifo_stress", "recovery")

    for index in range(16):
        start = len(tb.ahb.beats)
        address = 0x400 + index * 4
        await tb.send_aw(ident=index & 0xF, address=address, length=0, size=2, burst=int(Burst.INCR))
        await tb.get_b(ident=index & 0xF, response=AXI_OKAY)
        tb.check_ahb_beats(
            start_index=start, addresses=[address], write=True, size=2,
            burst=Burst.INCR, data=[0x8000_0000 + index],
        )
        tb.expected_write(address, 0x8000_0000 + index, 2)
        tb.coverage.sample_request(direction="WRITE", burst=Burst.INCR, size=2, beats=1, address=address, response=AXI_OKAY)
    tb.check_memory()


async def case_reset_recovery(tb: BridgeTestbench) -> None:
    # Stop an active AHB beat with HREADY low, assert reset, and prove no stale
    # response escapes.  A fresh post-reset command must still work.
    tb.ahb.schedule(waits=[8], errors=[False])
    await tb.send_aw(ident=10, address=0x500, length=0, size=2, burst=int(Burst.INCR))
    await tb.send_w(data=0x9000_0001, strb=0b1111, last=True)
    for _ in range(100):
        await RisingEdge(tb.dut.clk)
        await ReadOnly()
        # During the active data phase HTRANS describes the NEXT address;
        # this non-pipelined master correctly offers IDLE while data waits.
        if not int(tb.dut.hready.value):
            break
    else:
        raise AssertionError("failed to reach AHB wait state before reset")
    tb.coverage.mark("reset_point", "ahb_wait")
    # The wait-state observation is sampled in the read-only phase; advance
    # into a writable delta before driving synchronous reset.
    await Timer(1, unit="ps")
    await tb.reset(cycles=2)
    for _ in range(5):
        await RisingEdge(tb.dut.clk)
        await ReadOnly()
        assert not int(tb.dut.s_bvalid.value) and not int(tb.dut.s_rvalid.value), "stale response after reset recovery"

    # Cover the remaining externally meaningful reset insertion points.  Each
    # mini-case begins from an empty bridge and is followed by reset, so it also
    # checks that partial commands and queued response payloads are flushed.
    await tb.send_aw(ident=11, address=0x504, length=0, size=2, burst=int(Burst.INCR))
    tb.coverage.mark("reset_point", "aw_captured")
    await tb.reset(cycles=2)

    await tb.send_w(data=0x9000_0002, strb=0b1111, last=True)
    tb.coverage.mark("reset_point", "w_captured")
    await tb.reset(cycles=2)

    await tb.send_aw(ident=12, address=0x508, length=0, size=2, burst=int(Burst.INCR))
    await tb.send_w(data=0x9000_0003, strb=0b1111, last=True)
    for _ in range(100):
        await RisingEdge(tb.dut.clk)
        await ReadOnly()
        if int(tb.dut.s_bvalid.value):
            await Timer(1, unit="ps")
            break
    else:
        raise AssertionError("failed to reach B response before reset")
    tb.coverage.mark("reset_point", "b_stall")
    await tb.reset(cycles=2)

    await check_write(
        tb, ident=13, address=0x50C, size=2, burst=Burst.INCR, data=[0x9000_0004]
    )
    await tb.send_ar(ident=14, address=0x50C, length=0, size=2, burst=int(Burst.INCR))
    for _ in range(100):
        await RisingEdge(tb.dut.clk)
        await ReadOnly()
        if int(tb.dut.s_rvalid.value):
            await Timer(1, unit="ps")
            break
    else:
        raise AssertionError("failed to reach R response before reset")
    tb.coverage.mark("reset_point", "r_stall")
    await tb.reset(cycles=2)

    await check_write(
        tb, ident=15, address=0x510, size=2, burst=Burst.INCR, data=[0x9000_0005]
    )
    await check_read(tb, ident=0, address=0x510, size=2, burst=Burst.INCR, beats=1)


async def case_seeded_random_mix(tb: BridgeTestbench) -> None:
    randomizer = random.Random(0xA514_2026)
    base = 0x600
    for transaction in range(12):
        size = randomizer.choice([0, 1, 2])
        burst = randomizer.choice([Burst.FIXED, Burst.INCR, Burst.WRAP])
        beats = randomizer.choice([1, 2, 4, 8])
        if burst is Burst.WRAP and beats == 1:
            beats = 2
        step = 1 << size
        # WRAP address is deliberately somewhere inside its legal wrap block.
        if burst is Burst.WRAP:
            block = beats * step
            address = ((base + transaction * 0x40) // block) * block + randomizer.randrange(beats) * step
        else:
            address = (base + transaction * 0x40 + (randomizer.randrange(4) * step)) & ~(step - 1)
        ident = transaction & 0xF
        direction_write = randomizer.choice([True, False])
        if direction_write:
            values = [randomizer.getrandbits(32) & lane_mask(item, size) for item in __import__("reference_model").burst_addresses(address, size, beats - 1, burst, max_burst_beats=16)]
            await check_write(tb, ident=ident, address=address, size=size, burst=burst, data=values)
        else:
            await check_read(tb, ident=ident, address=address, size=size, burst=burst, beats=beats)


@cocotb.test()
async def full_protocol_regression(dut):
    """Run directed, error, stress, reset and seed-stable random scenarios."""

    coverage = FunctionalCoverage()
    tb = BridgeTestbench(dut, coverage)
    tb.start()
    await tb.reset()
    coverage.mark("reset_point", "idle")

    await case_single_and_narrow(tb)
    await case_burst_conversion(tb)
    await case_w_before_aw(tb)
    await case_strict_command_ordering(tb)
    await case_wait_states_and_axi_backpressure(tb)
    await case_illegal_requests(tb)
    await case_ahb_errors(tb)
    await case_fifo_full_and_recovery(tb)
    await case_reset_recovery(tb)
    await case_seeded_random_mix(tb)

    project_root = Path(__file__).resolve().parents[2]
    payload = coverage.write_report(project_root / "results" / "functional_coverage.json")
    cocotb.log.info("Functional regression complete: %d transaction-level coverage samples", payload["total_samples"])
