// Suppoting functions for Cortex-M Security Extensions
const builtin = @import("builtin");
const assert = @import("std").debug.assert;

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
/// `null`.
pub inline fn checkObject(comptime ty: type, ptr: usize, options: CheckOptions) ?*volatile ty {
    // Check alignment
    const alignment = @alignOf(ty);

    if ((ptr & ((1 << alignment) - 1)) != 0) {
        return null;
    }

    // Check access
    if (checkAddressRange(ptr, @sizeOf(ty), options)) {
        return @intToPtr(?*volatile ty, ptr);
    } else {
        return null;
    }
}

/// Check Non-Secure access permissions for a slice of element type `ty`
/// starting at `ptr`, containing `count` elements.
///
/// Returns a slice of type `[]volatile ty` if the check succeeds; otherwise,
/// `null`.
pub inline fn checkSlice(comptime ty: type, ptr: usize, count: usize, options: CheckOptions) ?[]volatile ty {
    // Check alignment
    const alignment = @alignOf(ty);

    if ((ptr & ((1 << alignment) - 1)) != 0) {
        return null;
    }

    // Check size
    var size: usize = undefined;
    if (!@mulWithOverflow(usize, count, @sizeOf(ty), &size)) {
        return null;
    }

    // Check access
    if (checkAddressRange(ptr, size, options)) {
        return @intToPtr([*]volatile ty, ptr)[0..size];
    } else {
        return null;
    }
}

/// Check Non-Secure access permissions for the specified address range.
///
/// Returns `false` if the check fail; otherwise, `true`.
///
/// This roughly follows the address range check intrinsic described in:
/// “ARM®v8-M Security Extensions: Requirements on Development Tools”
pub inline fn checkAddressRange(ptr: var, size: usize, options: CheckOptions) bool {
    const start = if (@typeOf(ptr) == usize) ptr else @ptrToInt(ptr);
    var end: usize = start;

    if (size > 0 and !@addWithOverflow(usize, start, size - 1, &end)) {
        // The check should fail if the address range wraps around
        return false;
    }

    const info1 = if (options.unpriv) ttat(start) else tta(start);
    const info2 = if (size > 1)
        (if (options.unpriv) ttat(start) else tta(start))
    else
        (info1);

    // The chcek should fail if the range crosses any SAU/IDAU/MPU region
    // boundary
    if (info1.value != info2.value) {
        return false;
    }

    return if (options.readwrite)
        (info1.flags.nonsecure_readwrite_ok)
    else
        (info1.flags.nonsecure_read_ok);
}

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
        extern fn veneer() linksection(".gnu.sgstubs") void {
            // See another comment regarding `.cpu`
            asm volatile (
                \\ .cpu cortex-m33
                \\
                \\ # Mark this function as a valid entry point.
                \\ sg
                \\
                \\ push {r7, lr}
                : // no output
                : // no input
            // Actually we don't modify any of them. They are needed
            // to make sure other instructions (specifically, the load of
            // `func`) aren't moved to the front of `sg`.
                : "memory", "r7"
            );
            asm volatile (
                \\ .cpu cortex-m33
                \\
                \\ # Call the original function
                \\ blx %[func]
                \\
                \\ # Clear caller-saved registers
                \\ # TODO: clear FP registers
                \\ mov r1, #0
                \\ mov r2, #0
                \\ mov r3, #0
                \\
                \\ # Return
                \\ pop {r7, lr}
                \\ bxns lr
                : // no output
                : [func] "{r7}" (func)
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
