"""A real cocotb/VPI probe for the free local simulation environment."""

import cocotb
from cocotb.triggers import RisingEdge


@cocotb.test()
async def clock_toggles_three_times(dut):
    """Prove cocotb can observe a signal in the Icarus simulation."""

    for _ in range(3):
        await RisingEdge(dut.clk)

    assert int(dut.clk.value) == 1
