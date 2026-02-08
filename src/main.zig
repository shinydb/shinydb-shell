const std = @import("std");
const shinydb = @import("shinydb_zig_client");
const ShinyDbClient = shinydb.ShinyDbClient;
const Query = shinydb.Query;
const yql = shinydb.yql;
const formatter = @import("formatter.zig");

// Command history manager
const CommandHistory = struct {
    commands: std.ArrayList([]const u8),
    current_index: ?usize = null,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) CommandHistory {
        return CommandHistory{
            .commands = .empty,
            .allocator = allocator,
        };
    }

    fn deinit(self: *CommandHistory) void {
        for (self.commands.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.commands.deinit(self.allocator);
    }

    fn add(self: *CommandHistory, cmd: []const u8) !void {
        const owned = try self.allocator.dupe(u8, cmd);
        try self.commands.append(self.allocator, owned);
        self.current_index = null; // Reset current position
    }

    fn getPrevious(self: *CommandHistory) ?[]const u8 {
        if (self.commands.items.len == 0) return null;

        if (self.current_index) |idx| {
            if (idx > 0) {
                self.current_index = idx - 1;
                return self.commands.items[idx - 1];
            }
        } else {
            // Start from the end
            self.current_index = self.commands.items.len - 1;
            return self.commands.items[self.commands.items.len - 1];
        }
        return null;
    }

    fn getNext(self: *CommandHistory) ?[]const u8 {
        if (self.current_index) |idx| {
            if (idx < self.commands.items.len - 1) {
                self.current_index = idx + 1;
                return self.commands.items[idx + 1];
            } else {
                self.current_index = null;
                return null;
            }
        }
        return null;
    }
};

fn enableRawMode(stdin_fd: std.posix.fd_t) !?std.posix.termios {
    const original = std.posix.tcgetattr(stdin_fd) catch |err| switch (err) {
        error.NotATerminal => return null,
        else => return err,
    };
    var raw = original;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;

    try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);
    return original;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line args for host/port
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var host: []const u8 = "127.0.0.1";
    var port: u16 = 23469;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            host = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port = std.fmt.parseInt(u16, args[i + 1], 10) catch 23469;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            printHelp();
            return;
        }
    }

    // Start REPL
    try runRepl(allocator, host, port);
}

fn printHelp() void {
    const help =
        \\shinydb-cli - shinydb Interactive Query Shell (YQL + Management)
        \\
        \\USAGE:
        \\    shinydb-cli [OPTIONS]
        \\
        \\OPTIONS:
        \\    --host <HOST>      Server host (default: 127.0.0.1)
        \\    --port <PORT>      Server port (default: 23469)
        \\    --help, -h         Show this help
        \\
        \\SHELL COMMANDS:
        \\    .help              Show detailed help
        \\    .exit, .quit       Exit the shell
        \\
        \\  Management:
        \\    .spaces            List all spaces
        \\    .stores [space]    List stores (optionally in a space)
        \\    .indexes [store]   List indexes (optionally for a store)
        \\    .users             List all users
        \\
        \\    .create space <name> [description]
        \\    .create store <space.store> [description]
        \\    .create index <space.store.index> <field> <type>
        \\    .create user <username> <password> <role>
        \\
        \\    .drop space <name>
        \\    .drop store <space.store>
        \\    .drop index <space.store.index>
        \\    .drop user <username>
        \\
        \\  Query:
        \\    .debug <query>     Parse YQL and show JSON (without executing)
        \\
        \\YQL SYNTAX:
        \\    space.store[.filter(...)][.orderBy(...)][.limit(n)]
        \\    space.store[.groupBy(...)][.aggregate(...)]
        \\
        \\QUICK EXAMPLES:
        \\    myapp.users.limit(10)
        \\    myapp.users.filter(age > 21)
        \\    myapp.orders.filter(status = "active").orderBy(date, desc).limit(5)
        \\
    ;
    std.debug.print("{s}", .{help});
}

fn runRepl(allocator: std.mem.Allocator, host: []const u8, port: u16) !void {
    // Setup I/O
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Create and connect client
    var client = try ShinyDbClient.init(allocator, io);
    defer client.deinit();

    std.debug.print("Connecting to shinydb at {s}:{d}...\n", .{ host, port });
    client.connect(host, port) catch |err| {
        std.debug.print("Connection failed: {}\n", .{err});
        std.debug.print("Make sure shinydb server is running.\n", .{});
        return;
    };
    defer client.disconnect();

    std.debug.print("Connected! Type .help for commands, .exit to quit.\n\n", .{});

    // Initialize command history
    var history = CommandHistory.init(allocator);
    defer history.deinit();

    // Read from stdin character by character to handle line input
    const stdin_fd: std.posix.fd_t = 0; // stdin is always fd 0
    var original_termios: ?std.posix.termios = null;
    original_termios = enableRawMode(stdin_fd) catch |err| blk: {
        std.debug.print("Warning: failed to enable raw mode: {}\n", .{err});
        break :blk null;
    };
    defer if (original_termios) |orig| {
        _ = std.posix.tcsetattr(stdin_fd, .FLUSH, orig) catch {};
    };
    var line_buf: [4096]u8 = undefined;
    var line_pos: usize = 0;

    while (true) {
        std.debug.print("shinydb> ", .{});
        line_pos = 0;

        // Read characters until newline
        while (line_pos < line_buf.len - 1) {
            var char_buf: [1]u8 = undefined;
            const bytes_read = std.posix.read(stdin_fd, &char_buf) catch |err| {
                std.debug.print("\nRead error: {}\n", .{err});
                return;
            };

            if (bytes_read == 0) {
                // EOF
                std.debug.print("\n", .{});
                return;
            }

            // Handle escape sequences for arrow keys (ESC [ A = up, ESC [ B = down)
            if (char_buf[0] == 27) { // ESC
                var seq_buf: [2]u8 = undefined;
                const seq_read = std.posix.read(stdin_fd, &seq_buf) catch 0;

                if (seq_read == 2 and seq_buf[0] == '[') {
                    if (seq_buf[1] == 'A') {
                        // Up arrow - retrieve previous command
                        if (history.getPrevious()) |prev_cmd| {
                            @memcpy(line_buf[0..prev_cmd.len], prev_cmd);
                            line_pos = prev_cmd.len;
                            // Redraw the line
                            std.debug.print("\r\x1B[2Kshinydb> ", .{});
                            std.debug.print("{s}", .{prev_cmd});
                            continue;
                        }
                    } else if (seq_buf[1] == 'B') {
                        // Down arrow - retrieve next command
                        if (history.getNext()) |next_cmd| {
                            @memcpy(line_buf[0..next_cmd.len], next_cmd);
                            line_pos = next_cmd.len;
                            // Redraw the line
                            std.debug.print("\r\x1B[2Kshinydb> ", .{});
                            std.debug.print("{s}", .{next_cmd});
                            continue;
                        } else {
                            // Clear the line if we've gone past history
                            line_pos = 0;
                            std.debug.print("\r\x1B[2Kshinydb> ", .{});
                            continue;
                        }
                    }
                }
                // If not a recognized escape sequence, ignore it
                continue;
            }

            // Handle Enter key (both \r and \n in raw mode)
            if (char_buf[0] == '\r' or char_buf[0] == '\n') {
                std.debug.print("\n", .{}); // Move to next line
                break;
            }

            // Handle backspace
            if (char_buf[0] == 127 or char_buf[0] == 8) {
                if (line_pos > 0) {
                    line_pos -= 1;
                    std.debug.print("\x08 \x08", .{});
                }
                continue;
            }

            // Echo regular characters
            line_buf[line_pos] = char_buf[0];
            line_pos += 1;
            std.debug.print("{c}", .{char_buf[0]});
        }

        const input = std.mem.trim(u8, line_buf[0..line_pos], " \t\r");

        if (input.len == 0) continue;

        // Add to history
        history.add(input) catch {};

        // Handle commands
        if (std.mem.startsWith(u8, input, ".")) {
            if (std.mem.eql(u8, input, ".exit") or std.mem.eql(u8, input, ".quit")) {
                std.debug.print("Goodbye!\n", .{});
                break;
            } else if (std.mem.eql(u8, input, ".help")) {
                printShellHelp();
            } else if (std.mem.eql(u8, input, ".cls")) {
                // Clear screen - print ANSI clear sequence or multiple newlines
                std.debug.print("\x1B[2J\x1B[H", .{});
            } else if (std.mem.eql(u8, input, ".spaces")) {
                listSpaces(client);
            } else if (std.mem.startsWith(u8, input, ".stores")) {
                if (input.len > 8) {
                    const space_name = std.mem.trim(u8, input[8..], " ");
                    listStores(client, space_name);
                } else {
                    listStores(client, null);
                }
            } else if (std.mem.startsWith(u8, input, ".indexes")) {
                if (input.len > 9) {
                    const store_name = std.mem.trim(u8, input[9..], " ");
                    listIndexes(client, store_name);
                } else {
                    listIndexes(client, null);
                }
            } else if (std.mem.eql(u8, input, ".users")) {
                listUsers(client);
            } else if (std.mem.startsWith(u8, input, ".create ")) {
                handleCreate(client, allocator, input[8..]);
            } else if (std.mem.startsWith(u8, input, ".drop ")) {
                handleDrop(client, input[6..]);
            } else if (std.mem.startsWith(u8, input, ".debug ")) {
                const query = std.mem.trim(u8, input[7..], " ");
                debugQuery(allocator, query);
            } else {
                std.debug.print("Unknown command: {s}\n", .{input});
                std.debug.print("Type .help for available commands.\n", .{});
            }
            continue;
        }

        // Execute YQL query
        executeQuery(allocator, client, io, input);
    }
}

fn printShellHelp() void {
    const help =
        \\
        \\GENERAL COMMANDS:
        \\    .help              Show this help
        \\    .cls               Clear screen
        \\    .exit, .quit       Exit the shell
        \\
        \\MANAGEMENT COMMANDS:
        \\    .spaces                     List all spaces
        \\    .stores [space]             List stores (all or in a specific space)
        \\    .indexes [store]            List indexes (all or for a specific store)
        \\    .users                      List all users
        \\
        \\    .create space <name> [desc]
        \\    .create store <space.store> [desc]
        \\    .create index <space.store.idx> <field> <String|I32|I64|F64|Boolean>
        \\    .create user <username> <password> <0=admin|1=read_write|2=read_only>
        \\
        \\    .drop space <name>
        \\    .drop store <space.store>
        \\    .drop index <space.store.idx>
        \\    .drop user <username>
        \\
        \\YQL SYNTAX:
        \\    space.store.filter(field op value).orderBy(field, asc|desc).limit(n)
        \\    space.store.groupBy(field1, field2).aggregate(name: func(field), ...)
        \\
        \\FILTER OPERATORS:
        \\    =, !=, >, >=, <, <=, ~(regex), in, contains, exists
        \\
        \\AGGREGATION FUNCTIONS:
        \\    count, sum(field), avg(field), min(field), max(field)
        \\
        \\QUERY EXAMPLES:
        \\    test_app.users.limit(10)
        \\    test_app.users.filter(age > 21).limit(5)
        \\    test_app.orders.filter(status = "active").orderBy(created_at, desc).limit(20)
        \\
        \\HISTORY:
        \\    ↑ / ↓ arrow keys    Navigate command history
        \\
    ;
    std.debug.print("{s}\n", .{help});
}

// ========== Management Commands ==========

fn listSpaces(client: *ShinyDbClient) void {
    const spaces = client.list(.Space, null) catch |err| {
        std.debug.print("Failed to list spaces: {}\n", .{err});
        return;
    };
    defer client.allocator.free(spaces);
    std.debug.print("Spaces: {s}\n", .{spaces});
}

fn listStores(client: *ShinyDbClient, space_filter: ?[]const u8) void {
    const stores = client.list(.Store, space_filter) catch |err| {
        std.debug.print("Failed to list stores: {}\n", .{err});
        return;
    };
    defer client.allocator.free(stores);
    if (space_filter) |space| {
        std.debug.print("Stores in '{s}': {s}\n", .{ space, stores });
    } else {
        std.debug.print("All stores: {s}\n", .{stores});
    }
}

fn listIndexes(client: *ShinyDbClient, store_filter: ?[]const u8) void {
    const indexes = client.list(.Index, store_filter) catch |err| {
        std.debug.print("Failed to list indexes: {}\n", .{err});
        return;
    };
    defer client.allocator.free(indexes);
    if (store_filter) |store| {
        std.debug.print("Indexes for '{s}': {s}\n", .{ store, indexes });
    } else {
        std.debug.print("All indexes: {s}\n", .{indexes});
    }
}

fn listUsers(client: *ShinyDbClient) void {
    const users = client.list(.User, null) catch |err| {
        std.debug.print("Failed to list users: {}\n", .{err});
        return;
    };
    defer client.allocator.free(users);
    std.debug.print("Users: {s}\n", .{users});
}

fn handleCreate(client: *ShinyDbClient, allocator: std.mem.Allocator, args: []const u8) void {
    var iter = std.mem.tokenizeAny(u8, args, " ");
    const entity_type = iter.next() orelse {
        std.debug.print("Usage: .create <space|store|index|user> <args...>\n", .{});
        return;
    };

    if (std.mem.eql(u8, entity_type, "space")) {
        const name = iter.next() orelse {
            std.debug.print("Usage: .create space <name> [description]\n", .{});
            return;
        };
        const desc = iter.rest();
        const description = if (desc.len > 0) desc else null;

        client.create(shinydb.Space{
            .id = 0,
            .ns = name,
            .description = description,
            .created_at = 0,
        }) catch |err| {
            std.debug.print("Failed to create space: {}\n", .{err});
            return;
        };
        std.debug.print("✓ Created space '{s}'\n", .{name});
    } else if (std.mem.eql(u8, entity_type, "store")) {
        const ns = iter.next() orelse {
            std.debug.print("Usage: .create store <space.store> [description]\n", .{});
            return;
        };
        const desc = iter.rest();
        const description = if (desc.len > 0) desc else null;

        client.create(shinydb.Store{
            .id = 0,
            .store_id = 0,
            .ns = ns,
            .description = description,
            .created_at = 0,
        }) catch |err| {
            std.debug.print("Failed to create store: {}\n", .{err});
            return;
        };
        std.debug.print("✓ Created store '{s}'\n", .{ns});
    } else if (std.mem.eql(u8, entity_type, "index")) {
        const ns = iter.next() orelse {
            std.debug.print("Usage: .create index <space.store.index> <field> <String|I32|I64|F64|Boolean>\n", .{});
            return;
        };
        const field = iter.next() orelse {
            std.debug.print("Usage: .create index <space.store.index> <field> <String|I32|I64|F64|Boolean>\n", .{});
            return;
        };
        const field_type_str = iter.next() orelse {
            std.debug.print("Usage: .create index <space.store.index> <field> <String|I32|I64|F64|Boolean>\n", .{});
            return;
        };

        const field_type: shinydb.FieldType = if (std.mem.eql(u8, field_type_str, "String"))
            .String
        else if (std.mem.eql(u8, field_type_str, "I32"))
            .I32
        else if (std.mem.eql(u8, field_type_str, "I64"))
            .I64
        else if (std.mem.eql(u8, field_type_str, "F64"))
            .F64
        else if (std.mem.eql(u8, field_type_str, "Boolean"))
            .Boolean
        else {
            std.debug.print("Invalid field type. Use: String, I32, I64, F64, or Boolean\n", .{});
            return;
        };

        client.create(shinydb.Index{
            .id = 0,
            .store_id = 0,
            .ns = ns,
            .field = field,
            .field_type = field_type,
            .unique = false,
            .description = null,
            .created_at = 0,
        }) catch |err| {
            std.debug.print("Failed to create index: {}\n", .{err});
            return;
        };
        std.debug.print("✓ Created index '{s}' on field '{s}' ({s})\n", .{ ns, field, field_type_str });
    } else if (std.mem.eql(u8, entity_type, "user")) {
        const username = iter.next() orelse {
            std.debug.print("Usage: .create user <username> <password> <0=admin|1=read_write|2=read_only>\n", .{});
            return;
        };
        const password = iter.next() orelse {
            std.debug.print("Usage: .create user <username> <password> <0=admin|1=read_write|2=read_only>\n", .{});
            return;
        };
        const role_str = iter.next() orelse {
            std.debug.print("Usage: .create user <username> <password> <0=admin|1=read_write|2=read_only>\n", .{});
            return;
        };
        const role = std.fmt.parseInt(u8, role_str, 10) catch {
            std.debug.print("Invalid role. Use: 0 (admin), 1 (read_write), or 2 (read_only)\n", .{});
            return;
        };

        client.create(shinydb.User{
            .id = 0,
            .username = username,
            .password_hash = password,
            .role = role,
            .created_at = 0,
        }) catch |err| {
            std.debug.print("Failed to create user: {}\n", .{err});
            return;
        };
        const role_name = switch (role) {
            0 => "admin",
            1 => "read_write",
            2 => "read_only",
            else => "unknown",
        };
        std.debug.print("✓ Created user '{s}' with role '{s}'\n", .{ username, role_name });
    } else {
        std.debug.print("Unknown entity type: {s}\n", .{entity_type});
        std.debug.print("Use: space, store, index, or user\n", .{});
    }
    _ = allocator;
}

fn handleDrop(client: *ShinyDbClient, args: []const u8) void {
    var iter = std.mem.tokenizeAny(u8, args, " ");
    const entity_type = iter.next() orelse {
        std.debug.print("Usage: .drop <space|store|index|user> <name>\n", .{});
        return;
    };
    const name = iter.next() orelse {
        std.debug.print("Usage: .drop {s} <name>\n", .{entity_type});
        return;
    };

    if (std.mem.eql(u8, entity_type, "space")) {
        client.drop(.Space, name) catch |err| {
            std.debug.print("Failed to drop space: {}\n", .{err});
            return;
        };
        std.debug.print("✓ Dropped space '{s}'\n", .{name});
    } else if (std.mem.eql(u8, entity_type, "store")) {
        client.drop(.Store, name) catch |err| {
            std.debug.print("Failed to drop store: {}\n", .{err});
            return;
        };
        std.debug.print("✓ Dropped store '{s}'\n", .{name});
    } else if (std.mem.eql(u8, entity_type, "index")) {
        client.drop(.Index, name) catch |err| {
            std.debug.print("Failed to drop index: {}\n", .{err});
            return;
        };
        std.debug.print("✓ Dropped index '{s}'\n", .{name});
    } else if (std.mem.eql(u8, entity_type, "user")) {
        client.drop(.User, name) catch |err| {
            std.debug.print("Failed to drop user: {}\n", .{err});
            return;
        };
        std.debug.print("✓ Dropped user '{s}'\n", .{name});
    } else {
        std.debug.print("Unknown entity type: {s}\n", .{entity_type});
        std.debug.print("Use: space, store, index, or user\n", .{});
    }
}

// ========== Query Commands ==========

fn debugQuery(allocator: std.mem.Allocator, query: []const u8) void {
    std.debug.print("Input: {s}\n", .{query});

    var query_ast = yql.parse(allocator, query) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return;
    };
    defer query_ast.deinit();

    std.debug.print("Parsed:\n", .{});
    std.debug.print("  Space: {s}\n", .{query_ast.space orelse "(none)"});
    std.debug.print("  Store: {s}\n", .{query_ast.store orelse "(none)"});
    std.debug.print("  Filters: {d}\n", .{query_ast.filters.items.len});
    if (query_ast.limit_val) |lim| {
        std.debug.print("  Limit: {d}\n", .{lim});
    }
    if (query_ast.skip_val) |sk| {
        std.debug.print("  Skip: {d}\n", .{sk});
    }
    if (query_ast.order_by) |ob| {
        std.debug.print("  OrderBy: {s} {s}\n", .{ ob.field, ob.direction.toString() });
    }

    const json = query_ast.toJson(allocator) catch |err| {
        std.debug.print("JSON error: {}\n", .{err});
        return;
    };
    defer allocator.free(json);
    std.debug.print("JSON: {s}\n", .{json});
}

fn executeQuery(allocator: std.mem.Allocator, client: *ShinyDbClient, io: anytype, input: []const u8) void {
    // Parse YQL
    var query_ast = yql.parse(allocator, input) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        std.debug.print("Hint: Use format space.store.filter(...).limit(n)\n", .{});
        return;
    };
    defer query_ast.deinit();

    // Get space and store
    const space_name = query_ast.space orelse {
        std.debug.print("Error: No space specified. Use format: space.store.filter(...)\n", .{});
        return;
    };
    const store_name = query_ast.store orelse {
        std.debug.print("Error: No store specified.\n", .{});
        return;
    };

    // Build full store namespace
    const store_ns = std.fmt.allocPrint(allocator, "{s}.{s}", .{ space_name, store_name }) catch {
        std.debug.print("Memory allocation failed\n", .{});
        return;
    };
    defer allocator.free(store_ns);

    // Use new Query builder API
    var query = Query.init(client);
    defer query.deinit();

    _ = query.space(space_name).store(store_name);

    // Apply filters
    for (query_ast.filters.items) |filter| {
        _ = query.where(filter.field, filter.op, filter.value);
    }

    // Apply limit
    if (query_ast.limit_val) |lim| {
        _ = query.limit(lim);
    }

    // Apply skip
    if (query_ast.skip_val) |sk| {
        _ = query.skip(sk);
    }

    // Apply orderBy
    if (query_ast.order_by) |ob| {
        _ = query.orderBy(ob.field, ob.direction);
    }

    // Apply groupBy (if any)
    if (query_ast.group_by) |gb| {
        for (gb.items) |field| {
            _ = query.groupBy(field);
        }
    }

    // Apply aggregations (if any)
    if (query_ast.aggregations) |aggs| {
        for (aggs.items) |agg| {
            // Use the internal aggregate method based on function type
            switch (agg.func) {
                .count => _ = query.count(agg.name),
                .sum => if (agg.field) |f| {
                    _ = query.sum(agg.name, f);
                },
                .avg => if (agg.field) |f| {
                    _ = query.avg(agg.name, f);
                },
                .min => if (agg.field) |f| {
                    _ = query.min(agg.name, f);
                },
                .max => if (agg.field) |f| {
                    _ = query.max(agg.name, f);
                },
            }
        }
    }

    // Execute query
    var response = query.run() catch |err| {
        std.debug.print("Query failed: {}\n", .{err});
        std.debug.print("Hint: Verify the space and store exist with .spaces and .stores\n", .{});
        return;
    };
    defer response.deinit();

    // Print result in tabular format
    if (response.data) |data| {
        var stdout_buf: [4096]u8 = undefined;
        const stdout_file = std.Io.File.stdout();
        var stdout_w = stdout_file.writer(io, &stdout_buf);
        const out_writer = &stdout_w.interface;

        formatter.printBsonArrayAsTable(allocator, data, out_writer) catch |err| {
            // Fallback error message only
            std.debug.print("Format error: {}\n", .{err});
        };

        // Flush the writer buffer to ensure output is displayed
        out_writer.flush() catch {};
    } else {
        std.debug.print("(no data)\n", .{});
    }
}
