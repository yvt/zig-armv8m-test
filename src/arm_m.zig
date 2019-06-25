/// Cortex-M SysTick timer.
///
/// The availability of SysTick(s) depends on the hardware configuration.
/// A PE implementing Armv8-M may include up to two instances of SysTick, each
/// for Secure and Non-Secure. Secure code can access the Non-Secure instance
/// via `sys_tick_ns` (`0xe002e010`).
pub const SysTick = struct {
    base: usize,

    const Self = @This();

    /// Construct a `SysTick` object using the specified MMIO base address.
    pub fn with_base(base: usize) Self {
        return Self{ .base = base };
    }

    /// SysTick Control and Status Register
    pub fn reg_csr(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base);
    }

    pub const CSR_COUNTFLAG: u32 = 1 << 16;
    pub const CSR_CLKSOURCE: u32 = 1 << 2;
    pub const CSR_TICKINT: u32 = 1 << 1;
    pub const CSR_ENABLE: u32 = 1 << 0;

    /// SysTick Reload Value Register
    pub fn reg_rvr(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x4);
    }

    /// SysTick Current Value Register
    pub fn reg_cvr(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x8);
    }

    /// SysTick Calibration Value Register
    pub fn reg_calib(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0xc);
    }
};

/// Represents the SysTick instance corresponding to the current security mode.
pub const sys_tick = SysTick.with_base(0xe000e010);

/// Represents the Non-Secure SysTick instance. This register is only accessible
/// by Secure mode.
pub const sys_tick_ns = SysTick.with_base(0xe002e010);
