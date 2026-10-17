const std = @import("std");
const testing = std.testing;
pub const lex = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const serializer = @import("serializer.zig");

pub const parse = parser.parse;
pub const decode = parser.decode;
pub const Value = parser.Value;
pub const Array = parser.Array;
pub const Table = parser.Table;

/// Serialize a value to the given out_stream.
///
/// Use this when you want to write a struct as the root table. When serializing
/// e.g. a number use `serializeKeyValue` instead, because in that case a key is required.
///
/// For a fixed-depth version that doesn't require an allocator, see `serializer.serializeFixedDepth`.
///
/// # Example
/// ```
/// const std = @import("std");
/// const tomlz = @import("tomlz");
///
/// var gpa_instance: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
/// defer _ = gpa_instance.deinit();
///
/// const point = .{
///     .x=4,
///     .y=2,
/// };
///
/// const io = init.io; // from `pub fn main(init: std.process.Init) !void`
/// var stdout_buffer: [1024]u8 = undefined;
/// var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
/// const stdout = &stdout_writer.interface;
/// try tomlz.serialize(
///     gpa_instance.allocator(),
///     stdout,
///     point,
/// );
///
/// try stdout.flush();
///
/// // Output:
/// // x = 4
/// // y = 2
/// ```
pub const serialize = serializer.serialize;

/// Serialize a key-value pair to the given out_stream.
///
/// If you want to write a struct as the root table, see `serialize`.
///
/// For a fixed-depth version that doesn't require an allocator, see `serializer.serializeKeyValueFixedDepth`.
/// # Example
/// ```
/// const std = @import("std");
/// const tomlz = @import("tomlz");
///
/// var gpa_instance: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
/// defer _ = gpa_instance.deinit();
///
/// const mynumber = 42;
///
/// const io = init.io; // from `pub fn main(init: std.process.Init) !void`
/// var stdout_buffer: [1024]u8 = undefined;
/// var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
/// const stdout = &stdout_writer.interface;
/// try tomlz.serializeKeyValue(
///     gpa_instance.allocator(),
///     stdout,
///     "some_key",
///     mynumber
/// );
///
/// try stdout.flush();
///
/// // Output:
/// // mynumber = 42
/// ```
pub const serializeKeyValue = serializer.serializeKeyValue;

test "refAllDecls" {
    const integration_tests = @import("integration_tests.zig");

    std.testing.refAllDecls(lex);
    std.testing.refAllDecls(parser);
    std.testing.refAllDecls(integration_tests);
    std.testing.refAllDecls(serializer);
}
