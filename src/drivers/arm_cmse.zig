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
