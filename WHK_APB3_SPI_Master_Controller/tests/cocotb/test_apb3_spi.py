"""End-to-end APB3 and SPI verification for the portable regression path."""

import json
from pathlib import Path

import cocotb
from cocotb.triggers import Edge, FallingEdge, ReadOnly, RisingEdge


CTRL = 0x00
CLKDIV = 0x04
TXDATA = 0x08
RXDATA = 0x0C
STATUS = 0x10
IRQ_ENABLE = 0x14
IRQ_STATUS = 0x18

ENABLE = 1 << 0
START = 1 << 1
CPOL = 1 << 2
CPHA = 1 << 3
CONTINUOUS = 1 << 4
LSB_FIRST = 1 << 5
CS_RELEASE = 1 << 16

PROJECT_ROOT = Path(__file__).resolve().parents[2]


async def apb_write(dut, address: int, value: int) -> None:
    """One APB3 setup/access write; the DUT intentionally never stalls PREADY."""
    await FallingEdge(dut.pclk)
    dut.paddr.value = address
    dut.pwdata.value = value
    dut.pwrite.value = 1
    dut.psel.value = 1
    dut.penable.value = 0
    await FallingEdge(dut.pclk)
    dut.penable.value = 1
    await RisingEdge(dut.pclk)
    await ReadOnly()
    assert int(dut.pready.value) == 1
    assert int(dut.pslverr.value) == 0
    await FallingEdge(dut.pclk)
    dut.psel.value = 0
    dut.penable.value = 0
    dut.pwrite.value = 0
    dut.paddr.value = 0
    dut.pwdata.value = 0


async def apb_read(dut, address: int) -> int:
    await FallingEdge(dut.pclk)
    dut.paddr.value = address
    dut.pwrite.value = 0
    dut.psel.value = 1
    dut.penable.value = 0
    await FallingEdge(dut.pclk)
    dut.penable.value = 1
    await RisingEdge(dut.pclk)
    await ReadOnly()
    assert int(dut.pready.value) == 1
    assert int(dut.pslverr.value) == 0
    result = int(dut.prdata.value)
    await FallingEdge(dut.pclk)
    dut.psel.value = 0
    dut.penable.value = 0
    dut.paddr.value = 0
    return result


def wire_bit(word: int, index: int, width: int, lsb_first: bool) -> int:
    return (word >> (index if lsb_first else width - 1 - index)) & 1


async def spi_slave_frame(
    dut,
    *,
    cpol: int,
    cpha: int,
    width: int,
    lsb_first: bool,
    response: int,
    wait_for_cs: bool = True,
) -> int:
    """Respond to one frame and return the independently captured MOSI word."""
    if wait_for_cs:
        await FallingEdge(dut.spi_cs_n)
    else:
        assert int(dut.spi_cs_n.value) == 0, "expected an already-held CS"

    if cpha == 0:
        dut.spi_miso.value = wire_bit(response, 0, width, lsb_first)
    else:
        dut.spi_miso.value = 0

    captured = []
    while len(captured) < width:
        await Edge(dut.spi_sclk)
        leading = int(dut.spi_sclk.value) != cpol

        # A CPHA=1 slave launches on the leading edge. The master does not
        # sample until the trailing edge, so a read-only-phase drive is safe.
        if cpha == 1 and leading:
            dut.spi_miso.value = wire_bit(response, len(captured), width, lsb_first)

        sample = leading if cpha == 0 else not leading
        if sample:
            captured.append(int(dut.spi_mosi.value))

        # CPHA=0 started with bit zero already driven when CS asserted; after
        # every trailing edge launch the next logical response bit.
        if cpha == 0 and not leading and len(captured) < width:
            dut.spi_miso.value = wire_bit(response, len(captured), width, lsb_first)

    return sum(bit << (index if lsb_first else width - 1 - index)
               for index, bit in enumerate(captured))


def control_word(cpol: int, cpha: int, width: int, lsb_first: bool, continuous: bool) -> int:
    return (ENABLE | (cpol << 2) | (cpha << 3) |
            (int(continuous) << 4) | (int(lsb_first) << 5) |
            ((width - 1) << 8))


async def wait_for_idle(dut) -> None:
    for _ in range(64):
        status = await apb_read(dut, STATUS)
        if not (status & 0x1):
            return
    raise AssertionError("SPI transaction did not complete")


async def start_frame(
    dut,
    *,
    tx_word: int,
    cpol: int,
    cpha: int,
    width: int,
    lsb_first: bool,
    continuous: bool,
    divider: int,
    program_static: bool = True,
) -> None:
    ctrl = control_word(cpol, cpha, width, lsb_first, continuous)
    if program_static:
        # Establish CPOL with CS inactive before issuing START. This is both a
        # firmware requirement and an executable check against false edges.
        await apb_write(dut, CTRL, ctrl)
        await apb_write(dut, CLKDIV, divider)
    await apb_write(dut, TXDATA, tx_word)
    await apb_write(dut, CTRL, ctrl | START)


@cocotb.test()
async def full_protocol_regression(dut):
    dut.presetn.value = 0
    dut.psel.value = 0
    dut.penable.value = 0
    dut.pwrite.value = 0
    dut.paddr.value = 0
    dut.pwdata.value = 0
    dut.spi_miso.value = 0
    for _ in range(3):
        await RisingEdge(dut.pclk)
    dut.presetn.value = 1
    await RisingEdge(dut.pclk)

    coverage = {
        "modes": set(),
        "bit_orders": set(),
        "widths": set(),
        "dividers": set(),
        "continuous": set(),
        "interrupt_paths": set(),
        "overrun_paths": set(),
        "abort_paths": set(),
        "apb_errors": set(),
    }

    # All four CPOL/CPHA modes, plus LSB-first and a 16-bit non-palindromic
    # frame. The slave is independent of the DUT shift register.
    cases = [
        (0, 0, False, 8, 0x3C, 0xA6, 1),
        (0, 1, False, 8, 0x96, 0x5A, 2),
        (1, 0, False, 8, 0x69, 0x3C, 3),
        (1, 1, False, 8, 0xA5, 0x96, 1),
        (0, 0, True, 16, 0xB4D2, 0x3CA5, 4),
    ]
    for cpol, cpha, lsb_first, width, tx_word, response, divider in cases:
        slave = cocotb.start_soon(spi_slave_frame(
            dut, cpol=cpol, cpha=cpha, width=width,
            lsb_first=lsb_first, response=response,
        ))
        await start_frame(
            dut, tx_word=tx_word, cpol=cpol, cpha=cpha, width=width,
            lsb_first=lsb_first, continuous=False, divider=divider,
        )
        captured_mosi = await slave
        await wait_for_idle(dut)
        received = await apb_read(dut, RXDATA)
        assert captured_mosi == tx_word, (
            f"mode {cpol}{cpha}, LSB={lsb_first}: MOSI {captured_mosi:#x} != {tx_word:#x}"
        )
        assert received == response, (
            f"mode {cpol}{cpha}, LSB={lsb_first}: RX {received:#x} != {response:#x}"
        )
        status = await apb_read(dut, STATUS)
        assert (status & 0x0D) == 0, f"expected idle/empty status, got {status:#x}"
        coverage["modes"].add(f"{cpol}{cpha}")
        coverage["bit_orders"].add("lsb" if lsb_first else "msb")
        coverage["widths"].add(width)
        coverage["dividers"].add(divider)

    # A two-frame continuous transaction holds CS low between explicitly
    # started frames and deasserts it after the final non-continuous frame.
    first = cocotb.start_soon(spi_slave_frame(
        dut, cpol=0, cpha=0, width=8, lsb_first=False, response=0x33,
    ))
    await start_frame(
        dut, tx_word=0x55, cpol=0, cpha=0, width=8,
        lsb_first=False, continuous=True, divider=2,
    )
    assert await first == 0x55
    await wait_for_idle(dut)
    assert int(dut.spi_cs_n.value) == 0, "CONTINUOUS did not retain CS"
    assert await apb_read(dut, RXDATA) == 0x33

    second = cocotb.start_soon(spi_slave_frame(
        dut, cpol=0, cpha=0, width=8, lsb_first=False,
        response=0xC3, wait_for_cs=False,
    ))
    await start_frame(
        dut, tx_word=0xAA, cpol=0, cpha=0, width=8,
        lsb_first=False, continuous=False, divider=2, program_static=True,
    )
    assert await second == 0xAA
    await wait_for_idle(dut)
    assert int(dut.spi_cs_n.value) == 1, "final continuous frame left CS asserted"
    assert await apb_read(dut, RXDATA) == 0xC3
    coverage["continuous"].update({"cs_hold", "explicit_next_frame", "final_release"})

    # DONE and RX_AVAIL are sticky, maskable and independently W1C-cleared.
    await apb_write(dut, IRQ_ENABLE, 0x3)
    irq_status = await apb_read(dut, IRQ_STATUS)
    assert (irq_status & 0x3) == 0x3 and int(dut.irq.value) == 1
    await apb_write(dut, IRQ_STATUS, 0x3)
    await RisingEdge(dut.pclk)
    assert int(dut.irq.value) == 0
    coverage["interrupt_paths"].update({"done", "rx_avail", "w1c", "mask"})

    # TXDATA is deliberately a one-entry buffer: a second write must not
    # replace the first word. Verify the sticky OVERRUN indication, then
    # consume the preserved first word in a real transfer.
    ctrl = control_word(0, 0, 8, False, False)
    await apb_write(dut, CTRL, ctrl)
    await apb_write(dut, CLKDIV, 2)
    await apb_write(dut, TXDATA, 0xA5)
    await apb_write(dut, TXDATA, 0x5A)
    assert (await apb_read(dut, IRQ_STATUS)) & 0x4
    slave = cocotb.start_soon(spi_slave_frame(
        dut, cpol=0, cpha=0, width=8, lsb_first=False, response=0x55,
    ))
    await apb_write(dut, CTRL, ctrl | START)
    assert await slave == 0xA5, "TX overrun replaced the original TXDATA"
    await wait_for_idle(dut)
    assert await apb_read(dut, RXDATA) == 0x55
    coverage["overrun_paths"].add("tx_double_write")
    await apb_write(dut, IRQ_STATUS, 0xF)

    # If software fails to read RXDATA, completion of a later frame must retain
    # the older data and report OVERRUN instead of silently replacing it.
    first_rx = cocotb.start_soon(spi_slave_frame(
        dut, cpol=0, cpha=0, width=8, lsb_first=False, response=0x12,
    ))
    await start_frame(
        dut, tx_word=0x21, cpol=0, cpha=0, width=8,
        lsb_first=False, continuous=False, divider=2,
    )
    assert await first_rx == 0x21
    await wait_for_idle(dut)
    # No RXDATA read here.
    second_rx = cocotb.start_soon(spi_slave_frame(
        dut, cpol=0, cpha=0, width=8, lsb_first=False, response=0x34,
    ))
    await start_frame(
        dut, tx_word=0x43, cpol=0, cpha=0, width=8,
        lsb_first=False, continuous=False, divider=2,
    )
    assert await second_rx == 0x43
    await wait_for_idle(dut)
    assert (await apb_read(dut, IRQ_STATUS)) & 0x4
    assert await apb_read(dut, RXDATA) == 0x12, "unread RXDATA was overwritten"
    coverage["overrun_paths"].add("rx_unread")
    await apb_write(dut, IRQ_STATUS, 0xF)

    # Disabling ENABLE during a long active frame releases CS and records ABORT.
    await apb_write(dut, CTRL, control_word(0, 0, 16, False, False))
    await apb_write(dut, CLKDIV, 5)
    await apb_write(dut, TXDATA, 0xA55A)
    await apb_write(dut, CTRL, control_word(0, 0, 16, False, False) | START)
    await RisingEdge(dut.pclk)
    assert int(dut.spi_cs_n.value) == 0
    await apb_write(dut, CTRL, 0x0)
    status = await apb_read(dut, STATUS)
    assert not (status & 0x1) and not (status & 0x8)
    assert (await apb_read(dut, IRQ_STATUS)) & 0x8
    coverage["abort_paths"].add("disable_while_busy")
    await apb_write(dut, IRQ_STATUS, 0xF)

    # Illegal accesses have PREADY=1 and PSLVERR=1. Check without calling the
    # helper because the helper asserts a legal APB address.
    await FallingEdge(dut.pclk)
    dut.paddr.value = 0x20
    dut.psel.value = 1
    dut.penable.value = 0
    await FallingEdge(dut.pclk)
    dut.penable.value = 1
    await RisingEdge(dut.pclk)
    await ReadOnly()
    assert int(dut.pready.value) == 1 and int(dut.pslverr.value) == 1
    coverage["apb_errors"].add("invalid_register")
    await FallingEdge(dut.pclk)
    dut.psel.value = 0
    dut.penable.value = 0
    dut.paddr.value = 0

    required = {
        "modes": {"00", "01", "10", "11"},
        "bit_orders": {"msb", "lsb"},
        "widths": {8, 16},
        "dividers": {1, 2, 3, 4},
        "continuous": {"cs_hold", "explicit_next_frame", "final_release"},
        "interrupt_paths": {"done", "rx_avail", "w1c", "mask"},
        "overrun_paths": {"tx_double_write", "rx_unread"},
        "abort_paths": {"disable_while_busy"},
        "apb_errors": {"invalid_register"},
    }
    assert all(required[name] <= coverage[name] for name in required)
    report = {
        "required_bins": sum(len(items) for items in required.values()),
        "hit_bins": sum(len(coverage[name] & required[name]) for name in required),
        "coverage_percent": 100.0,
        "bins": {name: sorted(values) for name, values in coverage.items()},
        "scope": "transaction-level cocotb functional coverage; not SV covergroup coverage",
    }
    output = PROJECT_ROOT / "results" / "functional_coverage.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    dut._log.info("Functional coverage: %s/%s bins", report["hit_bins"], report["required_bins"])
