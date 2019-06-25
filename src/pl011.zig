// Some parts of this source code were adapted from:
// https://github.com/altera-opensource/linux-socfpga/blob/master/drivers/tty/serial/mps2-uart.c
const format = @import("std").fmt.format;

const regs = struct {
    fn bit(comptime n: u32) u8 {
        return 1 << n;
    }

    const DATA: usize = 0x00;

    const STATE: usize = 0x04;
    const STATE_TX_FULL: u8 = bit(0);
    const STATE_RX_FULL: u8 = bit(1);
    const STATE_TX_OVERRUN: u8 = bit(2);
    const STATE_RX_OVERRUN: u8 = bit(3);

    const CTRL: usize = 0x08;
    const CTRL_TX_ENABLE: u8 = bit(0);
    const CTRL_RX_ENABLE: u8 = bit(1);
    const CTRL_TX_INT_ENABLE: u8 = bit(2);
    const CTRL_RX_INT_ENABLE: u8 = bit(3);
    const CTRL_TX_OVERRUN_INT_ENABLE: u8 = bit(4);
    const CTRL_RX_OVERRUN_INT_ENABLE: u8 = bit(5);

    const INT: usize = 0x0c;
    const INT_TX: u8 = bit(0);
    const INT_RX: u8 = bit(1);
    const INT_TX_OVERRUN: u8 = bit(2);
    const INT_RX_OVERRUN: u8 = bit(3);

    const BAUDDIV: usize = 0x10;
};

pub const Pl011 = struct {
    base: usize,

    const Self = @This();

    /// Construct a `Pl011` object using the specified MMIO base address.
    pub fn with_base(base: usize) Self {
        return Self{ .base = base };
    }

    fn reg_data(self: Self) *volatile u8 {
        return @intToPtr(*volatile u8, self.base + regs.DATA);
    }

    fn reg_state(self: Self) *volatile u8 {
        return @intToPtr(*volatile u8, self.base + regs.STATE);
    }

    fn reg_ctrl(self: Self) *volatile u8 {
        return @intToPtr(*volatile u8, self.base + regs.CTRL);
    }

    fn reg_int(self: Self) *volatile u8 {
        return @intToPtr(*volatile u8, self.base + regs.INT);
    }

    fn reg_bauddiv(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + regs.BAUDDIV);
    }

    pub fn configure(self: Self, system_core_clock: u32, baud_Rate: u32) void {
        self.reg_bauddiv().* = system_core_clock / baud_Rate;
        self.reg_ctrl().* = regs.CTRL_TX_ENABLE | regs.CTRL_RX_ENABLE;
    }

    pub fn try_write(self: Self, data: u8) bool {
        if ((self.reg_state().* & regs.STATE_TX_FULL) != 0) {
            return false;
        }

        self.reg_data().* = data;
        return true;
    }

    pub fn write(self: Self, data: u8) void {
        while (!self.try_write(data)) {}
    }

    pub fn write_slice(self: Self, data: []const u8) void {
        for (data) |b| {
            self.write(b);
        }
    }

    /// Render the format string `fmt` with `args` and transmit the output.
    pub fn print(self: Self, comptime fmt: []const u8, args: ...) void {
        format(self, error{}, Self.print_inner, fmt, args) catch unreachable;
    }

    fn print_inner(self: Self, data: []const u8) error{}!void {
        self.write_slice(data);
    }
};
