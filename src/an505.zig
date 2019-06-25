const Pl011 = @import("pl011.zig").Pl011;

/// UART 0 (secure) - J10 port
pub const Uart0 = Pl011.with_base(0x40200000);
