const std = @import("std");
const bson = @import("bson");

/// Helper function to write a string n times
fn writeStringNTimes(writer: anytype, str: []const u8, n: usize) !void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        try writer.writeAll(str);
    }
}

/// Format BSON data as JSON with pretty printing
pub fn formatBsonAsJson(allocator: std.mem.Allocator, bson_data: []const u8) ![]const u8 {
    // Try to parse as BSON document
    var doc = try bson.BsonDocument.init(allocator, bson_data, false);
    defer doc.deinit();

    // For now, return a placeholder
    var json_str: std.ArrayList(u8) = .empty;
    try json_str.appendSlice(allocator, "{ \"note\": \"BSON document formatting TODO\" }");
    return json_str.toOwnedSlice(allocator);
}

/// Print BSON array data in a hierarchical tree format
pub fn printBsonArrayAsTable(allocator: std.mem.Allocator, bson_data: []const u8, writer: anytype) !void {
    // Check if data starts with '[' - it's a JSON array of BSON documents
    if (bson_data.len == 0) {
        try writer.writeAll("(no data)\n");
        return;
    }

    // Parse array of BSON documents
    var documents: std.ArrayList(bson.BsonDocument) = .empty;
    defer {
        for (documents.items) |*doc| doc.deinit();
        documents.deinit(allocator);
    }

    var pos: usize = 0;

    // Parse concatenated BSON documents until end of data
    while (pos < bson_data.len) {

        // Read BSON document size (first 4 bytes, little endian)
        if (pos + 4 > bson_data.len) {
            try writer.writeAll("ERROR: Incomplete BSON document size\n");
            try writer.print("  Position: {d}, Remaining: {d}\n", .{ pos, bson_data.len - pos });
            return;
        }

        const doc_size = std.mem.readInt(i32, bson_data[pos .. pos + 4][0..4], .little);

        if (doc_size < 5 or pos + @as(usize, @intCast(doc_size)) > bson_data.len) {
            try writer.print("ERROR: Invalid BSON document size: {d} at position {d}\n", .{ doc_size, pos });
            return;
        }

        // Parse this BSON document
        const doc_bytes = bson_data[pos .. pos + @as(usize, @intCast(doc_size))];
        const doc = try bson.BsonDocument.init(allocator, doc_bytes, false);
        try documents.append(allocator, doc);

        pos += @as(usize, @intCast(doc_size));
    }

    if (documents.items.len == 0) {
        try writer.writeAll("(no results)\n");
        return;
    }

    // Print all documents as hierarchical trees
    for (documents.items, 0..) |*doc, doc_idx| {
        const is_last_doc = (doc_idx == documents.items.len - 1);
        const doc_prefix = if (is_last_doc) "└─" else "├─";
        const doc_indent_char = if (is_last_doc) " " else "│";

        try writer.print("{s}[Document {d}]:\n", .{ doc_prefix, doc_idx });

        const doc_indent = try std.fmt.allocPrint(allocator, "{s}  ", .{doc_indent_char});
        defer allocator.free(doc_indent);

        try printDocumentHierarchical(allocator, doc.*, writer, doc_indent);

        // Add visual separator between documents if not last
        if (!is_last_doc) {
            try writer.writeAll("│\n");
        }
    }

    // Print count
    try writer.print("\n({d} result{s})\n", .{ documents.items.len, if (documents.items.len == 1) @as([]const u8, "") else @as([]const u8, "s") });
}

/// Format a BSON value as a string for display
fn formatValue(allocator: std.mem.Allocator, value: bson.Value) ![]const u8 {
    switch (value) {
        .null => return try allocator.dupe(u8, "null"),
        .boolean => |b| return try allocator.dupe(u8, if (b) "true" else "false"),
        .int32 => |i| return try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .int64 => |i| return try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .double => |f| return try std.fmt.allocPrint(allocator, "{d:.2}", .{f}),
        .string => |s| return try allocator.dupe(u8, s),
        .object_id => |oid| {
            var buf: [24]u8 = undefined;
            const hex = "0123456789abcdef";
            for (oid.bytes, 0..) |byte, i| {
                buf[i * 2] = hex[byte >> 4];
                buf[i * 2 + 1] = hex[byte & 0x0F];
            }
            return try allocator.dupe(u8, &buf);
        },
        .datetime => |dt| return try std.fmt.allocPrint(allocator, "{d}", .{dt}),
        .timestamp => |ts| return try std.fmt.allocPrint(allocator, "{d}:{d}", .{ ts.timestamp, ts.increment }),
        .binary => |bin| return try std.fmt.allocPrint(allocator, "<binary:{d}bytes>", .{bin.data.len}),
        .document => return try allocator.dupe(u8, "[document]"),
        .array => |arr| {
            const len = try arr.len();
            return try std.fmt.allocPrint(allocator, "[{d} items]", .{len});
        },
        .regex => |r| return try std.fmt.allocPrint(allocator, "/{s}/{s}", .{ r.pattern, r.options }),
        .decimal128 => return try allocator.dupe(u8, "<decimal128>"),
    }
}

/// Check if a value type should be expanded hierarchically
fn isComplexValue(value: bson.Value) bool {
    return switch (value) {
        .document, .array => true,
        else => false,
    };
}

/// Print a BSON array hierarchically
fn printArrayHierarchical(allocator: std.mem.Allocator, array: bson.BsonArray, writer: anytype, indent: []const u8) anyerror!void {
    const len = try array.len();

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const is_last_item = (i == len - 1);
        const prefix = if (is_last_item) "└─" else "├─";
        const child_indent_char = if (is_last_item) " " else "│";

        try writer.print("{s}{s}[{d}]: ", .{ indent, prefix, i });

        if (try array.get(i)) |item_value| {
            defer {
                switch (item_value) {
                    .string => |s| allocator.free(s),
                    else => {},
                }
            }

            switch (item_value) {
                .document => |doc| {
                    try writer.writeAll("\n");
                    const new_indent = try std.fmt.allocPrint(allocator, "{s}{s}  ", .{ indent, child_indent_char });
                    defer allocator.free(new_indent);
                    try printDocumentHierarchical(allocator, doc, writer, new_indent);
                },
                .array => |nested_arr| {
                    const nested_len = try nested_arr.len();
                    try writer.print("[{d} items]\n", .{nested_len});
                    const new_indent = try std.fmt.allocPrint(allocator, "{s}{s}  ", .{ indent, child_indent_char });
                    defer allocator.free(new_indent);
                    try printArrayHierarchical(allocator, nested_arr, writer, new_indent);
                },
                else => {
                    const val_str = try formatValue(allocator, item_value);
                    defer allocator.free(val_str);
                    try writer.print("{s}\n", .{val_str});
                },
            }
        } else {
            try writer.writeAll("(missing)\n");
        }
    }
}

/// Print a BSON document hierarchically
fn printDocumentHierarchical(allocator: std.mem.Allocator, doc: bson.BsonDocument, writer: anytype, indent: []const u8) anyerror!void {
    var field_names = try doc.getFieldNames(allocator);
    defer {
        for (field_names) |name| allocator.free(name);
        allocator.free(field_names);
    }

    for (field_names, 0..) |field_name, idx| {
        const is_last = (idx == field_names.len - 1);
        const prefix = if (is_last) "└─" else "├─";
        const child_indent_char = if (is_last) " " else "│";

        try writer.print("{s}{s}{s}: ", .{ indent, prefix, field_name });

        if (try doc.getField(field_name)) |field_value| {
            defer {
                switch (field_value) {
                    .string => |s| allocator.free(s),
                    else => {},
                }
            }

            switch (field_value) {
                .document => |nested_doc| {
                    try writer.writeAll("\n");
                    const new_indent = try std.fmt.allocPrint(allocator, "{s}{s}  ", .{ indent, child_indent_char });
                    defer allocator.free(new_indent);
                    try printDocumentHierarchical(allocator, nested_doc, writer, new_indent);
                },
                .array => |arr| {
                    const len = try arr.len();
                    try writer.print("[{d} items]\n", .{len});
                    const new_indent = try std.fmt.allocPrint(allocator, "{s}{s}  ", .{ indent, child_indent_char });
                    defer allocator.free(new_indent);
                    try printArrayHierarchical(allocator, arr, writer, new_indent);
                },
                else => {
                    const val_str = try formatValue(allocator, field_value);
                    defer allocator.free(val_str);
                    try writer.print("{s}\n", .{val_str});
                },
            }
        } else {
            try writer.writeAll("null\n");
        }
    }
}

/// Print single BSON document in a hierarchical format
pub fn printBsonDocument(allocator: std.mem.Allocator, bson_data: []const u8, writer: anytype) !void {
    var doc = try bson.BsonDocument.init(allocator, bson_data, false);
    defer doc.deinit();

    try printDocumentHierarchical(allocator, doc, writer, "");
}
