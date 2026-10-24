"""Protocol-independent address and byte-lane oracle for the learning bridge.

This module deliberately does not model RTL state or UVM behaviour.  It is the
small, executable source of truth for AXI burst addressing and legal WSTRB
masks described in docs/bridge_spec.md.
"""

from __future__ import annotations

from enum import IntEnum
from math import log2
from typing import List


class Burst(IntEnum):
    FIXED = 0b00
    INCR = 0b01
    WRAP = 0b10


class RequestError(ValueError):
    """An AXI request that the learning bridge maps to DECERR."""


def _is_power_of_two(value: int) -> bool:
    return value > 0 and (value & (value - 1)) == 0


def beat_bytes(axsize: int) -> int:
    if axsize < 0:
        raise RequestError("AxSIZE must be non-negative")
    return 1 << axsize


def validate_request(
    start_addr: int,
    axsize: int,
    axlen: int,
    burst: Burst | int,
    *,
    data_bytes: int = 4,
    max_burst_beats: int = 16,
) -> Burst:
    """Validate the v0.1 learning-bridge subset and return normalized burst."""
    if not _is_power_of_two(data_bytes):
        raise ValueError("data_bytes must be a positive power of two")
    if start_addr < 0 or start_addr > 0xFFFF_FFFF:
        raise RequestError("address must fit the 32-bit interface")
    if axlen < 0:
        raise RequestError("AxLEN must be non-negative")
    if axlen + 1 > max_burst_beats:
        raise RequestError("burst exceeds MAX_BURST_BEATS")
    if axsize > int(log2(data_bytes)):
        raise RequestError("transfer width exceeds data bus width")
    step = beat_bytes(axsize)
    if start_addr % step:
        raise RequestError("unaligned address is unsupported in v0.1")
    try:
        kind = Burst(burst)
    except ValueError as error:
        raise RequestError("reserved AxBURST encoding") from error
    beats = axlen + 1
    if kind is Burst.FIXED and beats > 16:
        raise RequestError("AXI4 FIXED burst must not exceed 16 beats")
    if kind is Burst.WRAP and beats not in (2, 4, 8, 16):
        raise RequestError("WRAP burst must contain 2, 4, 8, or 16 beats")
    if kind is Burst.INCR:
        last_byte = start_addr + beats * step - 1
    elif kind is Burst.FIXED:
        last_byte = start_addr + step - 1
    else:
        # A naturally aligned legal WRAP block is <=64 bytes on this bus.
        # Check its actual range, not an imaginary linear INCR range.
        block_bytes = beats * step
        last_byte = (start_addr // block_bytes + 1) * block_bytes - 1
    if last_byte > 0xFFFF_FFFF or start_addr // 4096 != last_byte // 4096:
        raise RequestError("burst crosses a 4KB boundary or the address range")
    return kind


def burst_addresses(
    start_addr: int,
    axsize: int,
    axlen: int,
    burst: Burst | int,
    *,
    data_bytes: int = 4,
    max_burst_beats: int = 16,
) -> List[int]:
    """Return the exact AXI address for every beat in a supported burst."""
    kind = validate_request(
        start_addr, axsize, axlen, burst,
        data_bytes=data_bytes, max_burst_beats=max_burst_beats,
    )
    beats = axlen + 1
    step = beat_bytes(axsize)
    if kind is Burst.FIXED:
        return [start_addr] * beats
    if kind is Burst.INCR:
        return [start_addr + index * step for index in range(beats)]

    wrap_size = beats * step
    lower_boundary = (start_addr // wrap_size) * wrap_size
    upper_boundary = lower_boundary + wrap_size
    result = [start_addr]
    current = start_addr
    for _ in range(1, beats):
        next_linear = current + step
        current = lower_boundary if next_linear == upper_boundary else next_linear
        result.append(current)
    return result


def legal_wstrb(address: int, axsize: int, *, data_bytes: int = 4) -> int:
    """Return the only v0.1 supported contiguous WSTRB mask for one write beat."""
    if not _is_power_of_two(data_bytes):
        raise ValueError("data_bytes must be a positive power of two")
    step = beat_bytes(axsize)
    if step > data_bytes:
        raise RequestError("transfer width exceeds data bus width")
    if address % step:
        raise RequestError("unaligned address is unsupported in v0.1")
    lane = address % data_bytes
    if lane + step > data_bytes:
        raise RequestError("transfer crosses data bus word boundary")
    return ((1 << step) - 1) << lane


def is_legal_wstrb(address: int, axsize: int, wstrb: int, *, data_bytes: int = 4) -> bool:
    return wstrb == legal_wstrb(address, axsize, data_bytes=data_bytes)
