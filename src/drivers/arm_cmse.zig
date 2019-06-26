// Suppoting functions for Cortex-M Security Extensions

/// Call a niladic Non-Secure function.
pub inline fn callNs0(func: var) @typeInfo(@typeOf(func)).Fn.return_type.? {
    // This function call must never be inlined because we utilize a tail
    // function call in the inline assembler.
    return @noInlineCall(innerCallNs0, func);
}

fn innerCallNs0(func: var) @typeInfo(@typeOf(func)).Fn.return_type.? {
    comptime {
        if (@typeInfo(@typeOf(func)).Fn.args.len > 0) {
            @compileError("invalid number of formal parameters (expected 0)");
        }
    }

    // Specifying Armv8-M in `build.zig` won't work for some reason, so we have
    // to specify the architecture here using the `.cpu` directive
    asm volatile (
        \\ .cpu cortex-m33
        \\ bxns %[func]
        :
        : [func] "r" (func)
    );

    unreachable;
}

/// Security Attribution Unit.
pub const Sau = struct {
    base: usize,

    const Self = @This();

    /// Construct an `Sau` object using the specified MMIO base address.
    pub fn withBase(base: usize) Self {
        return Self{ .base = base };
    }

    // Register Accessors
    // -----------------------------------------------------------------------

    /// Control Register
    pub fn regCtrl(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base);
    }

    pub const CTRL_ENABLE: u32 = 1 << 0;
    pub const CTRL_ALLNS: u32 = 1 << 1;

    /// Region Base Address Register
    pub fn regRbar(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0xc);
    }

    /// Region Limit Address Register
    pub fn regRlar(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x10);
    }

    pub const RLAR_ENABLE: u32 = 1 << 0;
    pub const RLAR_NSC: u32 = 1 << 1;

    /// Region Number Register
    pub fn regRnar(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x8);
    }

    /// Type Register
    pub fn regType(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x4);
    }

    // Helper Functions
    // -----------------------------------------------------------------------

    /// Configure a single SAU region using `SauRegion`.
    pub fn setRegion(self: Self, i: u8, region: SauRegion) void {
        if ((region.start & 31) != 0) {
            unreachable;
        }
        if ((region.end & 31) != 0) {
            unreachable;
        }
        self.regRnar().* = i;
        self.regRlar().* = 0; // Disable the region first
        self.regRbar().* = region.start;
        self.regRlar().* = region.end | RLAR_ENABLE | if (region.nsc) RLAR_NSC else 0;
    }
};

/// Represents an instance of Security Attribution Unit.
pub const sau = Sau.withBase(0xe000edd0);

/// Describes a single SAU region.
pub const SauRegion = struct {
    /// The start address. Must be aligned to 32-byte blocks.
    start: u32,

    /// The end address (exclusive). Must be aligned to 32-byte blocks.
    end: u32,

    /// Non-Secure callable.
    nsc: bool = false,
};
