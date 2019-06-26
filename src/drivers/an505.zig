const Pl011 = @import("pl011.zig").Pl011;
const TzMpc = @import("tz_mpc.zig").TzMpc;

/// UART 0 (secure) - J10 port
pub const uart0 = Pl011.withBase(0x40200000);

pub const ssram1_mpc = TzMpc.withBase(0x58007000);
pub const ssram2_mpc = TzMpc.withBase(0x58008000);
pub const ssram3_mpc = TzMpc.withBase(0x58009000);
