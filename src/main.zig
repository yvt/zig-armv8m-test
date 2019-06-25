const std = @import("std");

const an505 = @import("an505.zig");

export fn main() void {
    // :( <https://github.com/ziglang/zig/issues/504>
    an505.Uart0.configure(25e6, 115200);
    an505.Uart0.print("(Hit ^A X to quit QEMU)\r\n");
    an505.Uart0.print("hello!\r\n");
}

/// Not a function, actually, but suppresses type error
extern fn _main_stack_top() void;

/// But this is really a function!
extern fn handle_reset() void;

/// Create an "unhandled exception" handler.
fn unhandled(comptime name: []const u8) extern fn () void {
    const ns = struct {
        extern fn handler() void {
            // TODO: display message
            an505.Uart0.print("caught an unhandled exception, system halted: {}\r\n", name);
            while (true) {}
        }
    };
    return ns.handler;
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
    unhandled("SysTick"), // SysTick
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
