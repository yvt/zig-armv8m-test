const Pl011 = @import("pl011.zig").Pl011;
const TzMpc = @import("tz_mpc.zig").TzMpc;

/// UART 0 (secure) - J10 port
pub const uart0 = Pl011.withBase(0x40200000);

pub const ssram1_mpc = TzMpc.withBase(0x58007000);
pub const ssram2_mpc = TzMpc.withBase(0x58008000);
pub const ssram3_mpc = TzMpc.withBase(0x58009000);

/// Security Privilege Control Block.
///
/// This is a part of Arm CoreLink SSE-200 Subsystem for Embedded.
pub const Spcb = struct {
    base: usize,

    const Self = @This();

    /// Construct a `Spcb` object using the specified MMIO base address.
    pub fn withBase(base: usize) Self {
        return Self{ .base = base };
    }

    /// Non Secure Callable Configuration for IDAU.
    pub fn regNsccfg(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x014);
    }

    pub const NSCCFG_RAMNSC: u32 = 1 << 1;
    pub const NSCCFG_CODENSC: u32 = 1 << 0;
};

/// Represents an instance of Security Privilege Control Block.
pub const spcb = Spcb.withBase(0x50080000);
