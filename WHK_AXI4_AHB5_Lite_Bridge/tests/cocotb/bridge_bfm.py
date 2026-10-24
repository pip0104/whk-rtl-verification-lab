"""Portable AXI/AHB verification components for the bridge regression.

The classes in this file are intentionally independent from the RTL
implementation.  The AXI master drives pins, the AHB slave observes pins and
the scoreboard calculates expected results from the documented protocol rules.
They provide the same three roles that an AXI agent, AHB agent and scoreboard
would provide in a UVM environment, while remaining executable with the
project's legal open-source simulator path.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Sequence
import json
import sys

import cocotb
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge, Timer

PROJECT_ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIR = PROJECT_ROOT / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from reference_model import Burst, burst_addresses, legal_wstrb


AXI_OKAY = 0b00
AXI_SLVERR = 0b10
AXI_DECERR = 0b11

AHB_NONSEQ = 0b10
AHB_SEQ = 0b11
AHB_SINGLE = 0b000
AHB_INCR = 0b001
AHB_WRAP4 = 0b010
AHB_INCR4 = 0b011
AHB_WRAP8 = 0b100
AHB_INCR8 = 0b101
AHB_WRAP16 = 0b110
AHB_INCR16 = 0b111


def lane_mask(address: int, size: int) -> int:
    """Return a 32-bit bit mask for the documented contiguous byte lanes."""

    strobe = legal_wstrb(address, size)
    mask = 0
    for lane in range(4):
        if strobe & (1 << lane):
            mask |= 0xFF << (lane * 8)
    return mask


def expected_hburst(burst: Burst, beats: int) -> int:
    return AHB_SINGLE


def expected_htrans(burst: Burst, beats: int, index: int) -> int:
    return AHB_NONSEQ


@dataclass(frozen=True)
class AhbBeat:
    address: int
    write: bool
    size: int
    burst: int
    trans: int
    data: int
    wait_cycles: int
    error: bool


class AhbMemorySlave:
    """AHB-Lite memory responder with deterministic waits and error injection."""

    def __init__(self, dut):
        self.dut = dut
        self.memory: dict[int, int] = {}
        self.beats: list[AhbBeat] = []
        self._wait_plan: list[int] = []
        self._error_plan: list[bool] = []
        self._active = False
        self._wait_left = 0
        self._active_waits = 0
        self._active_error = False
        self._recorded_current = False
        self._wait_snapshot: tuple[int, ...] | None = None
        self._pending: dict | None = None
        self._error_first_sent = False
        self.error_responses: list[tuple[int, int]] = []

    def schedule(self, *, waits: Iterable[int] = (), errors: Iterable[bool] = ()) -> None:
        """Append one wait/error choice for each future *real* AHB transfer."""

        waits = list(waits)
        errors = list(errors)
        if any(wait < 0 for wait in waits):
            raise ValueError("wait cycles must be non-negative")
        self._wait_plan.extend(waits)
        self._error_plan.extend(errors)

    def clear_observations(self) -> None:
        self.beats.clear()

    def read_word(self, address: int) -> int:
        return self.memory.get(address & ~0x3, 0)

    def write_word_masked(self, address: int, data: int, size: int) -> None:
        base = address & ~0x3
        mask = lane_mask(address, size)
        old = self.memory.get(base, 0)
        self.memory[base] = ((old & ~mask) | (data & mask)) & 0xFFFF_FFFF

    def reset_protocol_state(self) -> None:
        self._active = False
        self._wait_left = 0
        self._active_waits = 0
        self._active_error = False
        self._recorded_current = False
        self._wait_snapshot = None
        self._pending = None
        self._error_first_sent = False

    async def run(self) -> None:
        """Separate accepted address and following data phases.

        Capture pins before the active edge, then complete the OLD pending
        data phase and accept a NEW address only when HREADY was high.  Read
        data is deliberately poisoned with no data phase: sampling the address
        phase as if it were completion is observable, rather than hidden.
        ERROR is two cycles, HREADY low then high with HRESP high in both.
        This responder is driven only by public pins, never DUT state.
        """
        while True:
            await FallingEdge(self.dut.clk)
            await Timer(1, unit="ps")
            reset_active = int(self.dut.rst_n.value) == 0
            controls = (0,) * 9 if reset_active else tuple(int(getattr(self.dut, name).value) for name in (
                "haddr", "hwrite", "hsize", "hburst", "hprot", "htrans", "hmastlock", "hnonsec", "hwdata"
            ))
            ready = int(self.dut.hready.value)
            error = int(self.dut.hresp.value)
            await RisingEdge(self.dut.clk)
            await Timer(1, unit="ps")
            if reset_active:
                self.reset_protocol_state()
            else:
                if self._wait_snapshot is not None:
                    # A two-cycle ERROR permits cancelling the next address;
                    # write data for the current phase must still remain stable.
                    if error:
                        assert controls[-1] == self._wait_snapshot[-1], "AHB write data changed during ERROR"
                    else:
                        assert controls == self._wait_snapshot, "AHB control/data changed during data-phase wait"
                self._wait_snapshot = controls if not ready else None
                if self._pending is not None and error:
                    self.error_responses.append((error, ready))
                if ready:
                    if self._pending is not None:
                        p = self._pending
                        data = controls[-1]
                        self.beats.append(AhbBeat(
                            address=p["address"], write=p["write"], size=p["size"],
                            burst=p["burst"], trans=p["trans"], data=data,
                            wait_cycles=self._active_waits, error=bool(error),
                        ))
                        if p["write"] and not error:
                            self.write_word_masked(p["address"], data, p["size"])
                    self._pending = None
                    if controls[5] & 2:
                        self._pending = dict(address=controls[0], write=bool(controls[1]),
                                             size=controls[2], burst=controls[3], trans=controls[5])
                        self._active_waits = self._wait_plan.pop(0) if self._wait_plan else 0
                        self._wait_left = self._active_waits
                        self._active_error = self._error_plan.pop(0) if self._error_plan else False
                        self._error_first_sent = False

            self.dut.hrdata.value = 0xDEAD_5A5A if self._pending is None else self.read_word(self._pending["address"])
            if self._pending is None:
                self.dut.hready.value = 1
                self.dut.hresp.value = 0
            elif self._wait_left:
                self._wait_left -= 1
                self.dut.hready.value = 0
                self.dut.hresp.value = 0
            elif self._active_error and not self._error_first_sent:
                self._error_first_sent = True
                self.dut.hready.value = 0
                self.dut.hresp.value = 1
            else:
                self.dut.hready.value = 1
                self.dut.hresp.value = int(self._active_error)


class FunctionalCoverage:
    """Small, explicit functional-coverage model backed by the regression."""

    REQUIRED_BINS = {
        "direction": {"READ", "WRITE"},
        "burst": {"FIXED", "INCR", "WRAP", "RESERVED"},
        "size_bytes": {"1", "2", "4"},
        "beats": {"1", "2", "4", "8", "16"},
        "address_lane": {"0", "1", "2", "3"},
        "response": {"OKAY", "SLVERR", "DECERR"},
        "ahb_wait": {"0", "1", "2_3", "4_plus"},
        "error_beat": {"first", "middle", "last"},
        "reset_point": {"idle", "aw_captured", "w_captured", "ahb_wait", "b_stall", "r_stall"},
        "fifo_stress": {"full_backpressure", "recovery"},
    }

    def __init__(self) -> None:
        self.hits: dict[str, Counter[str]] = {
            "direction": Counter(),
            "burst": Counter(),
            "size_bytes": Counter(),
            "beats": Counter(),
            "address_lane": Counter(),
            "response": Counter(),
            "ahb_wait": Counter(),
            "error_beat": Counter(),
            "reset_point": Counter(),
            "fifo_stress": Counter(),
        }

    @staticmethod
    def _wait_bucket(wait_cycles: int) -> str:
        if wait_cycles == 0:
            return "0"
        if wait_cycles == 1:
            return "1"
        if wait_cycles <= 3:
            return "2_3"
        return "4_plus"

    def sample_request(
        self,
        *,
        direction: str,
        burst: Burst,
        size: int,
        beats: int,
        address: int,
        response: int,
    ) -> None:
        self.hits["direction"][direction] += 1
        self.hits["burst"][burst.name] += 1
        self.hits["size_bytes"][str(1 << size)] += 1
        self.hits["beats"][str(beats)] += 1
        self.hits["address_lane"][str(address & 0x3)] += 1
        self.hits["response"][{AXI_OKAY: "OKAY", AXI_SLVERR: "SLVERR", AXI_DECERR: "DECERR"}[response]] += 1

    def sample_ahb(self, beat: AhbBeat) -> None:
        self.hits["ahb_wait"][self._wait_bucket(beat.wait_cycles)] += 1

    def mark(self, point: str, value: str) -> None:
        self.hits[point][value] += 1

    def write_report(self, path: Path) -> dict:
        report = {name: dict(sorted(counter.items())) for name, counter in self.hits.items()}
        total_hits = sum(sum(counter.values()) for counter in self.hits.values())
        missing = [f"{point}:{name}" for point, bins in self.REQUIRED_BINS.items()
                   for name in sorted(bins) if self.hits[point][name] <= 0]
        required = sum(len(bins) for bins in self.REQUIRED_BINS.values())
        payload = {
            "format": "portable functional coverage v1",
            "note": "This is transaction-level functional coverage from the cocotb regression, not a commercial simulator code/covergroup report.",
            "total_samples": total_hits,
            "required_bins": required,
            "covered_required_bins": required - len(missing),
            "missing_required_bins": missing,
            "coverpoints": report,
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        if missing:
            raise AssertionError("Missing required functional bins: " + ", ".join(missing))
        return payload


class ProtocolMonitor:
    """External AXI protocol assertions usable with simulators lacking SVA."""

    def __init__(self, dut):
        self.dut = dut
        self._stalled: dict[str, tuple[int, ...] | None] = {
            "aw": None, "w": None, "ar": None, "b": None, "r": None,
        }

    async def run(self) -> None:
        while True:
            # Sample halfway between active edges, when each VALID/READY pair
            # describes the *next* handshake.  Post-rising-edge sampling can
            # mistake a just-completed final FIFO handshake for a stall because
            # READY may change combinationally with the updated FIFO count.
            await FallingEdge(self.dut.clk)
            await Timer(1, unit="ps")
            rst_value = str(self.dut.rst_n.value).lower()
            if "x" in rst_value or "z" in rst_value:
                continue
            if rst_value == "0":
                # Reset is synchronous.  The reset helper checks quiet output
                # after the active edge; this monitor only drops historical
                # stall state while reset is asserted.
                self._stalled = {name: None for name in self._stalled}
                continue

            channels = {
                "aw": (
                    int(self.dut.s_awvalid.value), int(self.dut.s_awready.value),
                    (int(self.dut.s_awid.value), int(self.dut.s_awaddr.value), int(self.dut.s_awlen.value),
                     int(self.dut.s_awsize.value), int(self.dut.s_awburst.value)),
                ),
                "w": (
                    int(self.dut.s_wvalid.value), int(self.dut.s_wready.value),
                    (int(self.dut.s_wdata.value), int(self.dut.s_wstrb.value), int(self.dut.s_wlast.value)),
                ),
                "ar": (
                    int(self.dut.s_arvalid.value), int(self.dut.s_arready.value),
                    (int(self.dut.s_arid.value), int(self.dut.s_araddr.value), int(self.dut.s_arlen.value),
                     int(self.dut.s_arsize.value), int(self.dut.s_arburst.value)),
                ),
                "b": (
                    int(self.dut.s_bvalid.value), int(self.dut.s_bready.value),
                    (int(self.dut.s_bid.value), int(self.dut.s_bresp.value)),
                ),
                "r": (
                    int(self.dut.s_rvalid.value), int(self.dut.s_rready.value),
                    (int(self.dut.s_rid.value), int(self.dut.s_rdata.value), int(self.dut.s_rresp.value),
                     int(self.dut.s_rlast.value)),
                ),
            }
            for name, (valid, ready, payload) in channels.items():
                previous = self._stalled[name]
                # When READY rises, the handshake has completed on this edge
                # and the source is free to change its payload afterwards.
                if previous is not None and not ready:
                    assert valid, f"AXI {name.upper()} VALID dropped while stalled"
                    assert payload == previous, f"AXI {name.upper()} payload changed while stalled"
                self._stalled[name] = payload if (valid and not ready) else None


class BridgeTestbench:
    """Pin-level AXI master plus independent scoreboard convenience methods."""

    def __init__(self, dut, coverage: FunctionalCoverage):
        self.dut = dut
        self.coverage = coverage
        self.ahb = AhbMemorySlave(dut)
        self.protocol = ProtocolMonitor(dut)
        self.expected_memory: dict[int, int] = {}

    def start(self) -> None:
        cocotb.start_soon(self.ahb.run())
        cocotb.start_soon(self.protocol.run())

    def _drive_defaults(self) -> None:
        for name in (
            "s_awid", "s_awaddr", "s_awlen", "s_awsize", "s_awburst", "s_awvalid",
            "s_wdata", "s_wstrb", "s_wlast", "s_wvalid",
            "s_arid", "s_araddr", "s_arlen", "s_arsize", "s_arburst", "s_arvalid",
        ):
            getattr(self.dut, name).value = 0
        self.dut.s_bready.value = 0
        self.dut.s_rready.value = 0
        self.dut.hready.value = 1
        self.dut.hresp.value = 0
        self.dut.hrdata.value = 0

    async def reset(self, *, cycles: int = 3) -> None:
        self._drive_defaults()
        self.dut.rst_n.value = 0
        for _ in range(cycles):
            await RisingEdge(self.dut.clk)
        self.dut.rst_n.value = 1
        await RisingEdge(self.dut.clk)
        await Timer(1, unit="ps")
        assert int(self.dut.s_bvalid.value) == 0 and int(self.dut.s_rvalid.value) == 0, "stale response after reset"

    async def send_aw(self, *, ident: int, address: int, length: int, size: int, burst: int) -> None:
        await FallingEdge(self.dut.clk)
        self.dut.s_awid.value = ident
        self.dut.s_awaddr.value = address
        self.dut.s_awlen.value = length
        self.dut.s_awsize.value = size
        self.dut.s_awburst.value = burst
        self.dut.s_awvalid.value = 1
        for _ in range(1000):
            # READY must be sampled before the active clock edge.  Sampling it
            # after the edge can miss a legal final handshake when FIFO state
            # changes combinationally in the same timestep.
            await Timer(1, unit="ps")
            will_handshake = int(self.dut.s_awready.value)
            await RisingEdge(self.dut.clk)
            if will_handshake:
                await FallingEdge(self.dut.clk)
                self.dut.s_awvalid.value = 0
                return
            await FallingEdge(self.dut.clk)
        raise AssertionError("AW channel timeout")

    async def send_w(self, *, data: int, strb: int, last: bool) -> None:
        await FallingEdge(self.dut.clk)
        self.dut.s_wdata.value = data
        self.dut.s_wstrb.value = strb
        self.dut.s_wlast.value = int(last)
        self.dut.s_wvalid.value = 1
        for _ in range(1000):
            await Timer(1, unit="ps")
            will_handshake = int(self.dut.s_wready.value)
            await RisingEdge(self.dut.clk)
            if will_handshake:
                await FallingEdge(self.dut.clk)
                self.dut.s_wvalid.value = 0
                return
            await FallingEdge(self.dut.clk)
        raise AssertionError("W channel timeout")

    async def send_ar(self, *, ident: int, address: int, length: int, size: int, burst: int) -> None:
        await FallingEdge(self.dut.clk)
        self.dut.s_arid.value = ident
        self.dut.s_araddr.value = address
        self.dut.s_arlen.value = length
        self.dut.s_arsize.value = size
        self.dut.s_arburst.value = burst
        self.dut.s_arvalid.value = 1
        for _ in range(1000):
            await Timer(1, unit="ps")
            will_handshake = int(self.dut.s_arready.value)
            await RisingEdge(self.dut.clk)
            if will_handshake:
                await FallingEdge(self.dut.clk)
                self.dut.s_arvalid.value = 0
                return
            await FallingEdge(self.dut.clk)
        raise AssertionError("AR channel timeout")

    async def get_b(self, *, ident: int, response: int, stall_cycles: int = 0) -> None:
        self.dut.s_bready.value = 0
        for _ in range(2000):
            await RisingEdge(self.dut.clk)
            await ReadOnly()
            if int(self.dut.s_bvalid.value):
                observed = (int(self.dut.s_bid.value), int(self.dut.s_bresp.value))
                assert observed == (ident, response), f"B mismatch: observed={observed}, expected={(ident, response)}"
                stable = observed
                for _ in range(stall_cycles):
                    await RisingEdge(self.dut.clk)
                    await ReadOnly()
                    assert int(self.dut.s_bvalid.value), "BVALID dropped under backpressure"
                    assert (int(self.dut.s_bid.value), int(self.dut.s_bresp.value)) == stable, "B changed under backpressure"
                await Timer(1, unit="ps")
                self.dut.s_bready.value = 1
                await RisingEdge(self.dut.clk)
                await Timer(1, unit="ps")
                self.dut.s_bready.value = 0
                return
        raise AssertionError("B response timeout")

    async def get_r(
        self,
        *,
        ident: int,
        expected: Sequence[tuple[int, int]],
        stall_cycles_first: int = 0,
    ) -> None:
        """Receive a sequence of (data, response) R beats and check RLAST."""

        self.dut.s_rready.value = 0
        for index, (data, response) in enumerate(expected):
            for _ in range(2000):
                await RisingEdge(self.dut.clk)
                await ReadOnly()
                if int(self.dut.s_rvalid.value):
                    observed = (
                        int(self.dut.s_rid.value),
                        int(self.dut.s_rdata.value),
                        int(self.dut.s_rresp.value),
                        int(self.dut.s_rlast.value),
                    )
                    wanted = (ident, data & 0xFFFF_FFFF, response, int(index == len(expected) - 1))
                    assert observed == wanted, f"R beat {index} mismatch: observed={observed}, expected={wanted}"
                    if index == 0:
                        for _ in range(stall_cycles_first):
                            await RisingEdge(self.dut.clk)
                            await ReadOnly()
                            assert int(self.dut.s_rvalid.value), "RVALID dropped under backpressure"
                            assert (
                                int(self.dut.s_rid.value), int(self.dut.s_rdata.value),
                                int(self.dut.s_rresp.value), int(self.dut.s_rlast.value),
                            ) == observed, "R changed under backpressure"
                    await Timer(1, unit="ps")
                    self.dut.s_rready.value = 1
                    await RisingEdge(self.dut.clk)
                    await Timer(1, unit="ps")
                    self.dut.s_rready.value = 0
                    break
            else:
                raise AssertionError(f"R response timeout at beat {index}")

    def expected_write(self, address: int, data: int, size: int) -> None:
        base = address & ~0x3
        mask = lane_mask(address, size)
        old = self.expected_memory.get(base, 0)
        self.expected_memory[base] = ((old & ~mask) | (data & mask)) & 0xFFFF_FFFF

    def expected_read(self, address: int, size: int) -> int:
        return self.expected_memory.get(address & ~0x3, 0) & lane_mask(address, size)

    def check_memory(self) -> None:
        for address, expected in self.expected_memory.items():
            observed = self.ahb.read_word(address)
            assert observed == expected, f"memory mismatch @0x{address:08x}: observed=0x{observed:08x}, expected=0x{expected:08x}"

    def check_ahb_beats(
        self,
        *,
        start_index: int,
        addresses: Sequence[int],
        write: bool,
        size: int,
        burst: Burst,
        data: Sequence[int] | None = None,
        errors: Sequence[bool] | None = None,
    ) -> list[AhbBeat]:
        observed = self.ahb.beats[start_index:]
        expected_count = len(addresses) if errors is None else next((index + 1 for index, value in enumerate(errors) if value), len(addresses))
        assert len(observed) == expected_count, f"AHB beat count mismatch: observed={len(observed)}, expected={expected_count}"
        for index, beat in enumerate(observed):
            assert beat.address == addresses[index], f"AHB address mismatch at beat {index}: 0x{beat.address:x} != 0x{addresses[index]:x}"
            assert beat.write is write, f"AHB direction mismatch at beat {index}"
            assert beat.size == size, f"AHB size mismatch at beat {index}"
            assert beat.burst == expected_hburst(burst, len(addresses)), f"AHB HBURST mismatch at beat {index}"
            assert beat.trans == expected_htrans(burst, len(addresses), index), f"AHB HTRANS mismatch at beat {index}"
            if data is not None and write:
                assert beat.data == (data[index] & lane_mask(addresses[index], size)), f"AHB data mismatch at beat {index}"
            self.coverage.sample_ahb(beat)
        return observed

    async def write_burst(
        self,
        *,
        ident: int,
        address: int,
        size: int,
        burst: Burst,
        data: Sequence[int],
        wstrbs: Sequence[int] | None = None,
        last_values: Sequence[bool] | None = None,
        response: int = AXI_OKAY,
        aw_first: bool = False,
        b_stall_cycles: int = 0,
    ) -> list[int]:
        beats = len(data)
        length = beats - 1
        addresses = burst_addresses(address, size, length, burst, max_burst_beats=16)
        if wstrbs is None:
            wstrbs = [legal_wstrb(item, size) for item in addresses]
        if last_values is None:
            last_values = [index == beats - 1 for index in range(beats)]

        async def send_all_w() -> None:
            for item, strobe, last in zip(data, wstrbs, last_values):
                await self.send_w(data=item, strb=strobe, last=last)

        if aw_first:
            await self.send_aw(ident=ident, address=address, length=length, size=size, burst=int(burst))
            await send_all_w()
        else:
            aw_task = cocotb.start_soon(self.send_aw(ident=ident, address=address, length=length, size=size, burst=int(burst)))
            w_task = cocotb.start_soon(send_all_w())
            await aw_task
            await w_task
        await self.get_b(ident=ident, response=response, stall_cycles=b_stall_cycles)
        self.coverage.sample_request(
            direction="WRITE", burst=burst, size=size, beats=beats, address=address, response=response
        )
        return addresses

    async def read_burst(
        self,
        *,
        ident: int,
        address: int,
        size: int,
        burst: Burst,
        expected: Sequence[tuple[int, int]],
        r_stall_cycles: int = 0,
    ) -> list[int]:
        beats = len(expected)
        length = beats - 1
        addresses = burst_addresses(address, size, length, burst, max_burst_beats=16)
        await self.send_ar(ident=ident, address=address, length=length, size=size, burst=int(burst))
        await self.get_r(ident=ident, expected=expected, stall_cycles_first=r_stall_cycles)
        self.coverage.sample_request(
            direction="READ", burst=burst, size=size, beats=beats, address=address, response=expected[0][1]
        )
        return addresses


def serialize_beats(beats: Sequence[AhbBeat]) -> list[dict]:
    return [asdict(beat) for beat in beats]
