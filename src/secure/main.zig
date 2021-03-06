const std = @import("std");

const arm_cmse = @import("../drivers/arm_cmse.zig");
const arm_m = @import("../drivers/arm_m.zig");
const an505 = @import("../drivers/an505.zig");

extern var __nsc_start: usize;
extern var __nsc_end: usize;

export fn main() void {
    // Enable SecureFault, UsageFault, BusFault, and MemManage for ease of
    // debugging. (Without this, they all escalate to HardFault)
    arm_m.scb.regShcsr().* =
        arm_m.Scb.SHCSR_MEMFAULTENA |
        arm_m.Scb.SHCSR_BUSFAULTENA |
        arm_m.Scb.SHCSR_USGFAULTENA |
        arm_m.Scb.SHCSR_SECUREFAULTENA;

    // Enable Non-Secure BusFault, HardFault, and NMI.
    // Prioritize Secure exceptions.
    arm_m.scb.regAircr().* =
        (arm_m.scb.regAircr().* & ~arm_m.Scb.AIRCR_VECTKEY_MASK) |
        arm_m.Scb.AIRCR_BFHFNMINS | arm_m.Scb.AIRCR_PRIS |
        arm_m.Scb.AIRCR_VECTKEY_MAGIC;

    // :( <https://github.com/ziglang/zig/issues/504>
    an505.uart0.configure(25e6, 115200);
    an505.uart0.print("(Hit ^A X to quit QEMU)\r\n");
    an505.uart0.print("The Secure code is running!\r\n");

    // Configure SysTick
    // -----------------------------------------------------------------------
    arm_m.sys_tick.regRvr().* = 1000 * 100; // fire every 100 milliseconds
    arm_m.sys_tick.regCsr().* = arm_m.SysTick.CSR_ENABLE |
        arm_m.SysTick.CSR_TICKINT;

    // Configure SAU
    // -----------------------------------------------------------------------
    const Region = arm_cmse.SauRegion;
    // AN505 ZBT SRAM (SSRAM1) Non-Secure alias
    arm_cmse.sau.setRegion(0, Region{ .start = 0x00200000, .end = 0x00400000 });
    // AN505 ZBT SRAM (SSRAM3) Non-Secure alias
    arm_cmse.sau.setRegion(1, Region{ .start = 0x28200000, .end = 0x28400000 });
    // The Non-Secure callable region
    arm_cmse.sau.setRegion(2, Region{
        .start = @ptrToInt(&__nsc_start),
        .end = @ptrToInt(&__nsc_end),
        .nsc = true,
    });

    // Configure MPCs and IDAU
    // -----------------------------------------------------------------------
    // Enable Non-Secure access to SSRAM1 (`0x[01]0200000`)
    // for the range `[0x200000, 0x3fffff]`.
    an505.ssram1_mpc.setEnableBusError(true);
    an505.ssram1_mpc.assignRangeToNonSecure(0x200000, 0x400000);

    // Enable Non-Secure access to SSRAM3 (`0x[23]8200000`)
    // for the range `[0, 0x1fffff]`.
    // - It seems that the range SSRAM3's MPC encompasses actually starts at
    //   `0x[23]8000000`.
    // - We actually use only the first `0x4000` bytes. However the hardware
    //   block size is larger than that and the rounding behavior of
    //   `tz_mpc.zig` is unspecified, so specify the larger range.
    an505.ssram3_mpc.setEnableBusError(true);
    an505.ssram3_mpc.assignRangeToNonSecure(0x200000, 0x400000);

    // Configure IDAU to enable Non-Secure Callable regions
    // for the code memory `[0x10000000, 0x1dffffff]`
    an505.spcb.regNsccfg().* |= an505.Spcb.NSCCFG_CODENSC;

    // Enable SAU
    // -----------------------------------------------------------------------
    arm_cmse.sau.regCtrl().* |= arm_cmse.Sau.CTRL_ENABLE;

    // Boot the Non-Secure code
    // -----------------------------------------------------------------------
    // Configure the Non-Secure exception vector table
    arm_m.scb_ns.regVtor().* = 0x00200000;

    an505.uart0.print("Booting the Non-Secure code...\r\n");

    // Call Non-Secure code's entry point
    const ns_entry = @intToPtr(*volatile fn () void, 0x00200004).*;
    _ = arm_cmse.nonSecureCall(ns_entry, 0, 0, 0, 0);

    an505.uart0.print("Non-Secure reset handler returned unexpectedly!\r\n");
    while (true) {}
}

/// The Non-Secure-callable function that outputs zero or more bytes to the
/// debug output.
extern fn nsDebugOutput(count: usize, ptr: usize, r2: usize, r32: usize) usize {
    const bytes = arm_cmse.checkSlice(u8, ptr, count, arm_cmse.CheckOptions{}) catch |err| {
        an505.uart0.print("warning: pointer security check failed: {}\r\n", err);
        an505.uart0.print("         count = {}, ptr = 0x{x}\r\n", count, ptr);
        return 0;
    };

    // Even if the permission check has succeeded, it's still unsafe to treat
    // Non-Secure pointers as normal pointers (this is why `bytes` is
    // `[]volatile u8`), so we can't use `writeSlice` here.
    for (bytes) |byte| {
        an505.uart0.write(byte);
    }

    return 0;
}

comptime {
    arm_cmse.exportNonSecureCallable("debugOutput", nsDebugOutput);
}

var counter: u8 = 0;

extern fn handleSysTick() void {
    counter +%= 1;
    an505.uart0.print("\r{}", "|\\-/"[counter % 4 ..][0..1]);
}

/// Not a function, actually, but suppresses type error
extern fn _main_stack_top() void;

/// But this is really a function!
extern fn handleReset() void;

/// Create an "unhandled exception" handler.
fn unhandled(comptime name: []const u8) extern fn () void {
    const ns = struct {
        extern fn handler() void {
            return unhandledInner(name);
        }
    };
    return ns.handler;
}

fn unhandledInner(name: []const u8) void {
    an505.uart0.print("caught an unhandled exception, system halted: {}\r\n", name);
    while (true) {}
}

export const exception_vectors linksection(".isr_vector") = [_]extern fn () void{
    _main_stack_top,
    handleReset,
    unhandled("NMI"), // NMI
    unhandled("HardFault"), // HardFault
    unhandled("MemManage"), // MemManage
    unhandled("BusFault"), // BusFault
    unhandled("UsageFault"), // UsageFault
    unhandled("SecureFault"), // SecureFault
    unhandled("Reserved 1"), // Reserved 1
    unhandled("Reserved 2"), // Reserved 2
    unhandled("Reserved 3"), // Reserved 3
    unhandled("SVCall"), // SVCall
    unhandled("DebugMonitor"), // DebugMonitor
    unhandled("Reserved 4"), // Reserved 4
    unhandled("PendSV"), // PendSV
    handleSysTick, // SysTick
    unhandled("External interrupt 0"), // External interrupt 0
    unhandled("External interrupt 1"), // External interrupt 1
    unhandled("External interrupt 2"), // External interrupt 2
    unhandled("External interrupt 3"), // External interrupt 3
    unhandled("External interrupt 4"), // External interrupt 4
    unhandled("External interrupt 5"), // External interrupt 5
    unhandled("External interrupt 6"), // External interrupt 6
    unhandled("External interrupt 7"), // External interrupt 7
    unhandled("External interrupt 8"), // External interrupt 8
};
