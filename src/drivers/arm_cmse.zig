// Suppoting functions for Cortex-M Security Extensions
const builtin = @import("builtin");
const assert = @import("std").debug.assert;

/// Call a Non-Secure function.
pub fn nonSecureCall(func: var, r0: usize, r1: usize, r2: usize, r3: usize) usize {
    const target = if (@typeOf(func) == usize) func else @ptrToInt(func);

    // Specifying Armv8-M in `build.zig` won't work for some reason, so we have
    // to specify the architecture here using the `.cpu` directive
    return asm volatile (
        \\ .cpu cortex-m33
        \\
        \\ # r7 is reserved (what?) and cannot be added to the clobber list
        \\ # r6 is not, but makes sure SP is aligned to 8-byte boundaries
        \\ push {r6, r7}
        \\
        \\ # Clear unbanked registers to remove confidential information.
        \\ # The compiler automatically saves their contents if they are needed.
        \\ mov r5, r4
        \\ mov r6, r4
        \\ mov r7, r4
        \\ mov r8, r4
        \\ mov r9, r4
        \\ mov r10, r4
        \\ mov r11, r4
        \\ mov r12, r4
        \\
        \\ # Lazily save floating-point registers
        \\ sub sp, #136
        \\ vlstm sp
        \\ msr apsr, r0
        \\
        \\ # Call the target
        \\ blxns r4
        \\
        \\ # Restore floating-point registers
        \\ vlldm sp
        \\ add sp, #136
        \\
        \\ pop {r6, r7}
        : [ret] "={r0}" (-> usize)
        : [r0] "{r0}" (r0),
          [r1] "{r1}" (r1),
          [r2] "{r2}" (r2),
          [r3] "{r3}" (r3),
          [func] "{r4}" (target & ~usize(1))
        : "r0", "r1", "r2", "r3", "r4", "r5", "r6", "r8", "r9", "r10", "r11", "r12"
    );
}

/// Generate a `TT` instruction..
pub inline fn tt(p: var) AddressInfo {
    return AddressInfo{
        .value = asm volatile (
            \\ .cpu cortex-m33
            \\ tt %0, %1
            : [out] "=r" (-> u32)
            : [p] "r" (p)
        ),
    };
}

/// Generate a `TT` instruction with the `A` flag (alternate security mode).
pub inline fn tta(p: var) AddressInfo {
    return AddressInfo{
        .value = asm volatile (
            \\ .cpu cortex-m33
            \\ tta %[out], %[p]
            : [out] "=r" (-> u32)
            : [p] "r" (p)
        ),
    };
}

/// Generate a `TT` instruction with the `A` flag (alternate security mode) and
/// `T` flag (non-privileged).
pub inline fn ttat(p: var) AddressInfo {
    return AddressInfo{
        .value = asm volatile (
            \\ .cpu cortex-m33
            \\ ttat %[out], %[p]
            : [out] "=r" (-> u32)
            : [p] "r" (p)
        ),
    };
}

/// Check Non-Secure access permissions for an object of type `ty` at `ptr`.
///
/// Returns `@intToPtr(*volatile ty, ptr)` if the check succeeds; otherwise,
/// an error value.
pub inline fn checkObject(comptime ty: type, ptr: usize, options: CheckOptions) CheckObjectError!*volatile ty {
    // Check alignment
    const alignment = @alignOf(ty);

    if ((ptr & ((1 << alignment) - 1)) != 0) {
        return CheckObjectError.Misaligned;
    }

    // Check access
    try checkAddressRange(ptr, @sizeOf(ty), options);

    return @intToPtr(*volatile ty, ptr);
}

pub const CheckObjectError = error{Misaligned} || CheckError;

/// Check Non-Secure access permissions for a slice of element type `ty`
/// starting at `ptr`, containing `count` elements.
///
/// Returns a slice of type `[]volatile ty` if the check succeeds; otherwise,
/// an error value..
pub inline fn checkSlice(comptime ty: type, ptr: usize, count: usize, options: CheckOptions) CheckSliceError![]volatile ty {
    // Check alignment
    const alignment = @alignOf(ty);

    if ((ptr & ((1 << alignment) - 1)) != 0) {
        return CheckSliceError.Misaligned;
    }

    // Check size
    var size: usize = undefined;
    if (@mulWithOverflow(usize, count, @sizeOf(ty), &size)) {
        return CheckSliceError.SizeTooLarge;
    }

    // Check access
    try checkAddressRange(ptr, size, options);

    return @intToPtr([*]volatile ty, ptr)[0..size];
}

pub const CheckSliceError = error{
    Misaligned,
    SizeTooLarge,
} || CheckError;

/// Check Non-Secure access permissions for the specified address range.
///
/// Returns an error value if the check fail; otherwise, `{}`.
///
/// This roughly follows the address range check intrinsic described in:
/// “ARM®v8-M Security Extensions: Requirements on Development Tools”
pub inline fn checkAddressRange(ptr: var, size: usize, options: CheckOptions) CheckError!void {
    const start = if (@typeOf(ptr) == usize) ptr else @ptrToInt(ptr);
    var end: usize = start;

    if (size > 0 and @addWithOverflow(usize, start, size - 1, &end)) {
        // The check should fail if the address range wraps around
        return CheckError.WrapsAround;
    }

    // TODO: Not sure how to handle `size == 0`. To be safe, we currently treat it as `1`

    const info1 = if (options.unpriv) ttat(start) else tta(start);
    const info2 = if (size > 1)
        (if (options.unpriv) ttat(start) else tta(start))
    else
        (info1);

    // The chcek should fail if the range crosses any SAU/IDAU/MPU region
    // boundary
    if (info1.value != info2.value) {
        return CheckError.CrossesRegionBoundary;
    }

    const ok = if (options.readwrite)
        (info1.flags.nonsecure_readwrite_ok)
    else
        (info1.flags.nonsecure_read_ok);

    return if (ok) {} else CheckError.Forbidden;
}

pub const CheckError = error{
    WrapsAround,
    CrossesRegionBoundary,
    Forbidden,
};

pub const CheckOptions = struct {
    /// Checks if the permissions have the `readwrite_ok` field set.
    readwrite: bool = false,

    /// Retrieves the unprivileged mode access permissions.
    unpriv: bool = false,
};

/// The address information returned by a `TT` instruction.
pub const AddressInfo = packed union {
    flags: packed struct {
        mpu_region: u8,
        sau_region: u8,
        mpu_region_valid: bool,
        sau_region_valid: bool,
        read_ok: bool,
        readwrite_ok: bool,
        nonsecure_read_ok: bool,
        nonsecure_readwrite_ok: bool,
        secure: bool,
        idau_region_valid: bool,
        idau_region: u8,
    },
    value: u32,
};

test "AddressInfo is word-sized" {
    assert(@sizeOf(AddressInfo) == 4);
}

/// Export a Non-Secure-callable function.
///
/// This function tries to achieve the effect similar to that of
/// `__attribute__((cmse_nonsecure_entry))`. It does not utilize the special
/// symbol `__acle_se_*` since it's probably not supported by the vanilla `lld`.
/// (TODO: needs confirmation)
/// It only supports a particular combination of parameter and return types.
/// Handling other combinations, especially those involving parameter passing
/// on the stack, is very difficult to implement here.
///
/// This comptime function generates a veneer function in the `.gnu.sgstubs`
/// section. The section must be configured as a Non-Secure-callable region for
/// it to be actually callable from Non-Secure.
/// The function also creates a marker symbol named by prepending the function
/// name with `__acle_se_` to instruct the linker to include the function in the
/// CMSE import library.
///
/// On return, it clears caller-saved registers (to prevent the leakage of
/// confidential information). (TODO: Clear FP registers)
///
/// See “ARM®v8-M Security Extensions: Requirements on Development Tools” for
/// other guidelines regarding the use of Non-Secure-callable functions.
pub fn exportNonSecureCallable(comptime name: []const u8, comptime func: extern fn (usize, usize, usize, usize) usize) void {
    const Veneer = struct {
        extern nakedcc fn veneer() linksection(".gnu.sgstubs") void {
            // See another comment regarding `.cpu`
            asm volatile (
                \\ .cpu cortex-m33
                \\
                \\ # Mark this function as a valid entry point.
                \\ sg
                \\
                \\ push {r4, lr}
                : // no output
                : // no input
            // Actually we don't modify it. This is needed
            // to make sure other instructions (specifically, the load of
            // `func`) aren't moved to the front of `sg`.
                : "memory", "r4"
            );
            asm volatile (
                \\ .cpu cortex-m33
                \\
                \\ # Call the original function
                \\ blx %[func]
                \\
                \\ pop {r4, lr}
                \\
                \\ # Clear caller-saved registers
                \\ # TODO: clear FP registers
                \\ mov r1, lr
                \\ mov r2, lr
                \\ mov r3, lr
                \\ mov ip, lr
                \\ msr apsr, lr
                \\
                \\ # Return
                \\ bxns lr
                : // no output
                : [func] "{r4}" (func)
            );

            unreachable;
        }
    };
    @export(name, Veneer.veneer, builtin.GlobalLinkage.Strong);
    @export("__acle_se_" ++ name, Veneer.veneer, builtin.GlobalLinkage.Strong);
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
        self.regRlar().* = (region.end - 32) | RLAR_ENABLE | if (region.nsc) RLAR_NSC else 0;
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
