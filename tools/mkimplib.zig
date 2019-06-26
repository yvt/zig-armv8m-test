const std = @import("std");
const process = std.process;
const fs = std.fs;

pub fn main() !void {
    // Since this is a short-lived program, we deliberately leak memory.
    // In case we want to release something, use the C allocator.
    const allocator = std.heap.c_allocator;

    const args = try process.argsAlloc(allocator);

    // The output file
    const output = try fs.File.openWrite(args[2]);
    defer output.close();

    try output.write("# TODO: impllib");
}
