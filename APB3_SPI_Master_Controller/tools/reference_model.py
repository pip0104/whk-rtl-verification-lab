"""Small executable oracle for the APB3 SPI master's frame-level behavior.

The model intentionally contains no RTL state-machine code.  It describes the
wire ordering and timing quantities that the scoreboard and documentation use:
all SPI modes have 2 * frame_bits SCLK transitions; CPHA selects which of the
leading/trailing edges samples MISO; CPOL selects the idle level.
"""

from dataclasses import dataclass
from typing import List, Tuple


@dataclass(frozen=True)
class SpiConfig:
    cpol: int
    cpha: int
    divider: int
    bits: int
    lsb_first: bool = False
    continuous: bool = False

    def validate(self) -> None:
        if self.cpol not in (0, 1) or self.cpha not in (0, 1):
            raise ValueError("CPOL and CPHA must each be 0 or 1")
        if not 0 <= self.divider <= 0xFFFF:
            raise ValueError("divider must fit the 16-bit register")
        if not 1 <= self.bits <= 32:
            raise ValueError("frame width must be in 1..32 bits")


def wire_bits(word: int, bits: int, lsb_first: bool) -> List[int]:
    """Return logical bits in their MOSI/MISO wire transmission order."""
    if not 1 <= bits <= 32:
        raise ValueError("bits must be in 1..32")
    if word < 0 or word >= (1 << 32):
        raise ValueError("word must be an unsigned 32-bit value")
    positions = range(bits) if lsb_first else range(bits - 1, -1, -1)
    return [(word >> position) & 1 for position in positions]


def assemble_bits(bits_on_wire: List[int], bits: int, lsb_first: bool) -> int:
    """Convert captured wire-order bits back to a 32-bit logical word."""
    if len(bits_on_wire) != bits:
        raise ValueError("captured bit count does not match configured frame width")
    result = 0
    positions = range(bits) if lsb_first else range(bits - 1, -1, -1)
    for bit, position in zip(bits_on_wire, positions):
        if bit not in (0, 1):
            raise ValueError("SPI wire bits must be 0 or 1")
        result |= bit << position
    return result


def edge_plan(config: SpiConfig) -> List[Tuple[str, int, bool]]:
    """Describe all SCLK edges as (kind, resulting_level, is_sample_edge)."""
    config.validate()
    plan: List[Tuple[str, int, bool]] = []
    level = config.cpol
    for _ in range(config.bits):
        level ^= 1
        plan.append(("leading", level, config.cpha == 0))
        level ^= 1
        plan.append(("trailing", level, config.cpha == 1))
    return plan


def expected_half_period_pclks(config: SpiConfig) -> int:
    """The RTL's CLKDIV encoding: value N yields N+1 PCLKs per half phase."""
    config.validate()
    return config.divider + 1


def transfer(tx_word: int, slave_response: int, config: SpiConfig) -> Tuple[List[int], int]:
    """Return master MOSI stream and reconstructed master RXDATA word."""
    config.validate()
    mosi = wire_bits(tx_word, config.bits, config.lsb_first)
    miso = wire_bits(slave_response, config.bits, config.lsb_first)
    assert sum(1 for _, _, sample in edge_plan(config) if sample) == config.bits
    return mosi, assemble_bits(miso, config.bits, config.lsb_first)

