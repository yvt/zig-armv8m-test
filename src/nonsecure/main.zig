const std = @import("std");

export fn main() void {
    // TODO
    while (true) {}
}

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
    // TODO: do something!
    while (true) {}
}

/// Not a function, actually, but suppresses type error
extern fn _main_stack_top() void;

/// But this is really a function!
extern fn handle_reset() void;

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
};
