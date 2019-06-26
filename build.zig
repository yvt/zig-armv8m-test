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

    // The Secure part
    const exe_s_name = if (want_gdb) "secure-dbg" else "secure";
    const exe_s = b.addExecutable(exe_s_name, "src/secure.zig");
    exe_s.setLinkerScriptPath("src/secure/linker.ld");
    exe_s.setTarget(arch, .freestanding, .eabi);
    exe_s.setBuildMode(mode);
    exe_s.addAssemblyFile("src/common/startup.s");
    exe_s.setOutputDir("zig-cache");
    // TODO: "-mthumb -mfloat-abi=soft -msoft-float -march=armv8-m.main");

    // The Non-Secure part
    const exe_ns_name = if (want_gdb) "nonsecure-dbg" else "nonsecure";
    const exe_ns = b.addExecutable(exe_ns_name, "src/nonsecure.zig");
    exe_ns.setLinkerScriptPath("src/nonsecure/linker.ld");
    exe_ns.setTarget(arch, .freestanding, .eabi);
    exe_ns.setBuildMode(mode);
    exe_ns.addAssemblyFile("src/common/startup.s");
    exe_ns.setOutputDir("zig-cache");

    const exe_both = b.step("build", "Build Secure and Non-Secure executables");
    exe_both.dependOn(&exe_s.step);
    exe_both.dependOn(&exe_ns.step);

    const qemu = b.step("qemu", "Run the program in qemu");
    var qemu_args = std.ArrayList([]const u8).init(b.allocator);

    const qemu_device_arg = try std.fmt.allocPrint(
        b.allocator,
        "loader,file={}",
        exe_ns.getOutputPath(),
    );
    try qemu_args.appendSlice([_][]const u8{
        "qemu-system-arm",
        "-kernel",
        exe_s.getOutputPath(),
        "-device",
        qemu_device_arg,
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
    run_qemu.step.dependOn(exe_both);

    b.default_step.dependOn(exe_both);
}
