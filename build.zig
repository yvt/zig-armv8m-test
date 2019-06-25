const builtin = @import("builtin");
const std = @import("std");
const Builder = @import("std").build.Builder;

// Mostly based on <https://github.com/andrewrk/clashos/blob/master/build.zig>

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const want_gdb = b.option(bool, "gdb", "Build for using gdb with qemu") orelse false;

    // TODO: `v8m_mainline` causes the following error during `ar`:
    //       `error: instruction variant requires ARMv6 or later`
    const arch = builtin.Arch{ .thumb = .v7m };

    const exec_name = if (want_gdb) "test-dbg" else "test";
    const exe = b.addExecutable(exec_name, "src/main.zig");
    exe.setLinkerScriptPath("src/linker.ld");
    exe.setTarget(arch, .freestanding, .eabi);
    exe.setBuildMode(mode);
    exe.addAssemblyFile("src/startup.s");
    exe.setOutputDir("zig-cache");
    // TODO: "-mthumb -mfloat-abi=soft -msoft-float -march=armv8-m.main");

    const qemu = b.step("qemu", "Run the OS in qemu");
    var qemu_args = std.ArrayList([]const u8).init(b.allocator);
    try qemu_args.appendSlice([_][]const u8{
        "qemu-system-arm",
        "-kernel",
        exe.getOutputPath(),
        "-machine",
        "mps2-an505",
        "-nographic",
        "-d",
        "guest_errors",
    });
    if (want_gdb) {
        try qemu_args.appendSlice([_][]const u8{ "-S", "-s" });
    }
    const run_qemu = b.addSystemCommand(qemu_args.toSliceConst());
    qemu.dependOn(&run_qemu.step);
    run_qemu.step.dependOn(&exe.step);

    b.default_step.dependOn(&exe.step);
}
