const std = @import("std");

const arm_cmse = @import("../drivers/arm_cmse.zig");
const arm_m = @import("../drivers/arm_m.zig");
const an505 = @import("../drivers/an505.zig");

export fn main() void {
    // Enable SecureFault, UsageFault, BusFault, and MemManage for ease of
    // debugging. (Without this, they all escalate to HardFault)
    arm_m.scb.reg_shcsr().* =
        arm_m.Scb.SHCSR_MEMFAULTENA |
        arm_m.Scb.SHCSR_BUSFAULTENA |
        arm_m.Scb.SHCSR_USGFAULTENA |
        arm_m.Scb.SHCSR_SECUREFAULTENA;

    // :( <https://github.com/ziglang/zig/issues/504>
    an505.uart0.configure(25e6, 115200);
    an505.uart0.print("(Hit ^A X to quit QEMU)\r\n");
    an505.uart0.print("The Secure code is running!\r\n");

    // Configure SysTick
    arm_m.sys_tick.reg_rvr().* = 1000 * 100; // fire every 100 milliseconds
    arm_m.sys_tick.reg_csr().* = arm_m.SysTick.CSR_ENABLE |
        arm_m.SysTick.CSR_TICKINT;

    // TODO: Configure SAU
    // TODO: Configure SSRAM1 MPC
    // TODO: Configure IRAM MPC

    an505.uart0.print("Booting the Non-Secure code...\r\n");

    // Call Non-Secure code's entry point
    const ns_entry = @intToPtr(*volatile fn()void, 0x00200004).*;
    arm_cmse.call_ns_0(ns_entry);

    an505.uart0.print("Non-Secure reset handler returned unexpectedly!\r\n");
    while (true) {}
}

var counter: u8 = 0;

extern fn handle_sys_tick() void {
    counter +%= 1;
    an505.uart0.print("\r\x08{}", "|\\-/"[counter % 4..][0..1]);
}

/// Not a function, actually, but suppresses type error
extern fn _main_stack_top() void;

/// But this is really a function!
extern fn handle_reset() void;

/// Create an "unhandled exception" handler.
fn unhandled(comptime name: []const u8) extern fn () void {
    const ns = struct {
        extern fn handler() void {
            return unhandled_inner(name);
        }
    };
    return ns.handler;
}

fn unhandled_inner(name: []const u8) void {
    an505.uart0.print("caught an unhandled exception, system halted: {}\r\n", name);
    while (true) {}
}

export const exception_vectors linksection(".isr_vector") = [_]extern fn () void{
    _main_stack_top,
    handle_reset,
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
    handle_sys_tick, // SysTick
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
