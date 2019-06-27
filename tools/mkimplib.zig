const std = @import("std");
const process = std.process;
const elf = std.elf;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const AppError = error {
    SymsSectionNotFound,
    StrtabSectionNotFound,
    UnexpectedEof,
};

pub fn main() !void {
    // Since this is a short-lived program, we deliberately leak memory.
    // In case we want to release something, use the C allocator.
    const allocator = std.heap.c_allocator;

    const args = try process.argsAlloc(allocator);

    // The input ELF file
    var input_file = try fs.File.openRead(args[1]);
    defer input_file.close();
    var input_elf: elf.Elf = undefined;
    var input_stream = FileStream.new(&input_file);
    try input_elf.openStream(
        allocator,
        &input_stream.seekable,
        &input_stream.in,
    );

    // Read the symbol table.
    // We currently assume the object file is in the little-endian format.
    const syms_hdr = (try input_elf.findSection(".symtab")) orelse
        return AppError.SymsSectionNotFound;
    try input_file.seekTo(syms_hdr.offset);

    const Sym = struct {
        addr: u32,
        name_offset: u32,
        name: []u8,
    };
    const syms = try allocator.alloc(Sym, syms_hdr.size / @sizeOf(elf.Elf32_Sym));
    for (syms) |*sym| {
        var elf_sym: elf.Elf32_Sym = undefined;

        const num_read = try input_file.read(
            @ptrCast([*]u8, &elf_sym)[0 .. @sizeOf(elf.Elf32_Sym)]);

        if (num_read < @sizeOf(elf.Elf32_Sym)) {
            return AppError.UnexpectedEof;
        }

        sym.addr = elf_sym.st_value;
        sym.name_offset = elf_sym.st_name;
    }

    const strtab_hdr = (try input_elf.findSection(".strtab")) orelse
        return AppError.SymsSectionNotFound;

    for (syms) |*sym| {
        sym.name = try getString(allocator, &input_elf, strtab_hdr, sym.name_offset);
    }

    // Create a hash set of symbol names to be exported.
    var entry_sym_map = AutoHashMap([]const u8, void).init(allocator);
    const entry_prefix = "__acle_se_";
    for (syms) |*sym| {
        if (mem.startsWith(u8, sym.name, entry_prefix)) {
            const bare_name = sym.name[entry_prefix.len ..];
            _ = try entry_sym_map.put(bare_name, {});
        }
    }

    // The output file
    // (Ideally this could be stdout, but `build.zig` doesn't let us redirect it.)
    const output_file = try fs.File.openWrite(args[2]);
    var output_stream = output_file.outStream();
    defer output_stream.file.close();

    try output_stream.stream.write(".syntax unified\n");

    for (syms) |*sym| {
        if (!entry_sym_map.contains(sym.name)){
            continue;
        }

        try output_stream.stream.print(".set {}, 0x{x}\n", sym.name, sym.addr);
        try output_stream.stream.print(".global {}\n", sym.name);
    }
}

fn getString(allocator: *Allocator, e: *elf.Elf, strtab: *const elf.SectionHeader, at: u32) ![]u8 {
    var list = ArrayList(u8).init(allocator);
    errdefer list.deinit();

    const name_offset = strtab.offset + at;
    try e.seekable_stream.seekTo(name_offset);

    while (true) {
        const b = try e.in_stream.readByte();
        if (b == 0) {
            break;
        }
        try list.append(b);
    }

    return list.toOwnedSlice();
}

const AnyerrorSeekableStream = io.SeekableStream(anyerror, anyerror);
const AnyerrorInStream = io.InStream(anyerror);
const FileStream = struct {
    file: *fs.File,
    seekable: AnyerrorSeekableStream,
    in: AnyerrorInStream,

    const Self = @This();

    fn new(file: *fs.File) Self {
        return Self {
            .file = file,
            .seekable = AnyerrorSeekableStream{
                .seekToFn = seekToFn,
                .seekByFn = seekByFn,
                .getPosFn = getPosFn,
                .getEndPosFn = getEndPosFn,
            },
            .in = AnyerrorInStream{
                .readFn = readFn,
            },
        };
    }

    fn readFn(in_stream: *AnyerrorInStream, buffer: []u8) anyerror!usize {
        const self = @fieldParentPtr(FileStream, "in", in_stream);
        return self.file.read(buffer);
    }

    fn seekToFn(seekable_stream: *AnyerrorSeekableStream, pos: u64) anyerror!void {
        const self = @fieldParentPtr(FileStream, "seekable", seekable_stream);
        return self.file.seekTo(pos);
    }

    fn seekByFn(seekable_stream: *AnyerrorSeekableStream, amt: i64) anyerror!void {
        const self = @fieldParentPtr(FileStream, "seekable", seekable_stream);
        return self.file.seekBy(amt);
    }

    fn getEndPosFn(seekable_stream: *AnyerrorSeekableStream) anyerror!u64 {
        const self = @fieldParentPtr(FileStream, "seekable", seekable_stream);
        return self.file.getEndPos();
    }

    fn getPosFn(seekable_stream: *AnyerrorSeekableStream) anyerror!u64 {
        const self = @fieldParentPtr(FileStream, "seekable", seekable_stream);
        return self.file.getPos();
    }
};
