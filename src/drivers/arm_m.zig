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
    pub fn withBase(base: usize) Self {
        return Self{ .base = base };
    }

    /// SysTick Control and Status Register
    pub fn regCsr(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base);
    }

    pub const CSR_COUNTFLAG: u32 = 1 << 16;
    pub const CSR_CLKSOURCE: u32 = 1 << 2;
    pub const CSR_TICKINT: u32 = 1 << 1;
    pub const CSR_ENABLE: u32 = 1 << 0;

    /// SysTick Reload Value Register
    pub fn regRvr(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x4);
    }

    /// SysTick Current Value Register
    pub fn regCvr(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x8);
    }

    /// SysTick Calibration Value Register
    pub fn regCalib(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0xc);
    }
};

/// Represents the SysTick instance corresponding to the current security mode.
pub const sys_tick = SysTick.withBase(0xe000e010);

/// Represents the Non-Secure SysTick instance. This register is only accessible
/// by Secure mode (Armv8-M or later).
pub const sys_tick_ns = SysTick.withBase(0xe002e010);

/// Nested Vectored Interrupt Controller.
pub const Nvic = struct {
    base: usize,

    const Self = @This();

    /// Construct an `Nvic` object using the specified MMIO base address.
    pub fn withBase(base: usize) Self {
        return Self{ .base = base };
    }

    // Register Accessors
    // -----------------------------------------------------------------------

    /// Interrupt Set Enable Register.
    pub fn regIser(self: Self) *volatile [16]u32 {
        return @intToPtr(*volatile [16]u32, self.base);
    }

    /// Interrupt Clear Enable Register.
    pub fn regIcer(self: Self) *volatile [16]u32 {
        return @intToPtr(*volatile [16]u32, self.base + 0x80);
    }

    /// Interrupt Set Pending Register.
    pub fn regIspr(self: Self) *volatile [16]u32 {
        return @intToPtr(*volatile [16]u32, self.base + 0x100);
    }

    /// Interrupt Clear Pending Register.
    pub fn regIcpr(self: Self) *volatile [16]u32 {
        return @intToPtr(*volatile [16]u32, self.base + 0x180);
    }

    /// Interrupt Active Bit Register.
    pub fn regIabr(self: Self) *volatile [16]u32 {
        return @intToPtr(*volatile [16]u32, self.base + 0x200);
    }

    /// Interrupt Target Non-Secure Register (Armv8-M or later). RAZ/WI from
    /// Non-Secure.
    pub fn regItns(self: Self) *volatile [16]u32 {
        return @intToPtr(*volatile [16]u32, self.base + 0x280);
    }

    /// Interrupt Priority Register.
    pub fn regIpri(self: Self) *volatile [512]u8 {
        return @intToPtr(*volatile [512]u8, self.base + 0x300);
    }

    // Helper functions
    // -----------------------------------------------------------------------
    // Note: Interrupt numbers are different from exception numbers.
    // An exception number `Interrupt_IRQn(i)` corresponds to an interrupt
    // number `i`.

    /// Enable the interrupt number `irq`.
    pub fn enableIrq(self: Self, irq: usize) void {
        self.reg_iser()[irq >> 5] = u32(1) << @truncate(u5, irq);
    }

    /// Disable the interrupt number `irq`.
    pub fn disableIrq(self: Self, irq: usize) void {
        self.reg_icer()[irq >> 5] = u32(1) << @truncate(u5, irq);
    }

    /// Set the priority of the interrupt number `irq` to `pri`.
    pub fn setIrqPriority(self: Self, irq: usize, pri: u8) void {
        self.reg_ipri()[irq] = pri;
    }
};

/// Represents the Nested Vectored Interrupt Controller instance corresponding
/// to the current security mode.
pub const nvic = Nvic.withBase(0xe000e100);

/// Represents the Non-Secure Nested Vectored Interrupt Controller instance.
/// This register is only accessible by Secure mode (Armv8-M or later).
pub const nvic_ns = Nvic.withBase(0xe002e100);

/// System Control Block.
pub const Scb = struct {
    base: usize,

    const Self = @This();

    /// Construct an `Nvic` object using the specified MMIO base address.
    pub fn withBase(base: usize) Self {
        return Self{ .base = base };
    }

    // Register Accessors
    // -----------------------------------------------------------------------

    /// System Handler Control and State Register
    pub fn regShcsr(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x124);
    }

    pub const SHCSR_MEMFAULTACT: u32 = 1 << 0;
    pub const SHCSR_BUSFAULTACT: u32 = 1 << 1;
    pub const SHCSR_HARDFAULTACT: u32 = 1 << 2;
    pub const SHCSR_USGFAULTACT: u32 = 1 << 3;
    pub const SHCSR_SECUREFAULTACT: u32 = 1 << 4;
    pub const SHCSR_NMIACT: u32 = 1 << 5;
    pub const SHCSR_SVCCALLACT: u32 = 1 << 7;
    pub const SHCSR_MONITORACT: u32 = 1 << 8;
    pub const SHCSR_PENDSVACT: u32 = 1 << 10;
    pub const SHCSR_SYSTICKACT: u32 = 1 << 11;
    pub const SHCSR_USGFAULTPENDED: u32 = 1 << 12;
    pub const SHCSR_MEMFAULTPENDED: u32 = 1 << 13;
    pub const SHCSR_BUSFAULTPENDED: u32 = 1 << 14;
    pub const SHCSR_SYSCALLPENDED: u32 = 1 << 15;
    pub const SHCSR_MEMFAULTENA: u32 = 1 << 16;
    pub const SHCSR_BUSFAULTENA: u32 = 1 << 17;
    pub const SHCSR_USGFAULTENA: u32 = 1 << 18;
    pub const SHCSR_SECUREFAULTENA: u32 = 1 << 19;
    pub const SHCSR_SECUREFAULTPENDED: u32 = 1 << 20;
    pub const SHCSR_HARDFAULTPENDED: u32 = 1 << 21;

    /// Application Interrupt and Reset Control Register
    pub fn regAircr(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x10c);
    }

    pub const AIRCR_VECTCLRACTIVE: u32 = 1 << 1;
    pub const AIRCR_SYSRESETREQ: u32 = 1 << 2;
    pub const AIRCR_SYSRESETREQS: u32 = 1 << 3;
    pub const AIRCR_DIT: u32 = 1 << 4;
    pub const AIRCR_IESB: u32 = 1 << 5;
    pub const AIRCR_PRIGROUP_SHIFT: u5 = 8;
    pub const AIRCR_PRIGROUP_MASK: u32 = 0b111 << AIRCR_PRIGROUP_SHIFT;
    pub const AIRCR_BFHFNMINS: u32 = 1 << 13;
    pub const AIRCR_PRIS: u32 = 1 << 14;
    pub const AIRCR_ENDIANNESS: u32 = 1 << 15;
    pub const AIRCR_VECTKEY_SHIFT: u5 = 16;
    pub const AIRCR_VECTKEY_MASK: u32 = 0xffff << AIRCR_VECTKEY_SHIFT;
    pub const AIRCR_VECTKEY_MAGIC: u32 = 0x05fa;

    /// Vector Table Offset Register
    pub fn regVtor(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x108);
    }
};

/// Represents the System Control Block instance corresponding to the current
/// security mode.
pub const scb = Scb.withBase(0xe000ec00);

/// Represents the System Control Block instance for Non-Secure mode.
/// This register is only accessible by Secure mode (Armv8-M or later).
pub const scb_ns = Scb.withBase(0xe002ec00);

/// Exception numbers defined by Arm-M.
pub const irqs = struct {
    pub const Reset_IRQn: usize = 1;
    pub const Nmi_IRQn: usize = 2;
    pub const SecureHardFault_IRQn: usize = 3;
    pub const MemManageFault_IRQn: usize = 4;
    pub const BusFault_IRQn: usize = 5;
    pub const UsageFault_IRQn: usize = 6;
    pub const SecureFault_IRQn: usize = 7;
    pub const SvCall_IRQn: usize = 11;
    pub const DebugMonitor_IRQn: usize = 12;
    pub const PendSv_IRQn: usize = 14;
    pub const SysTick_IRQn: usize = 15;
    pub const InterruptBase_IRQn: usize = 16;

    pub fn interruptIRQn(i: usize) usize {
        return @This().InterruptBase_IRQn + i;
    }
};
