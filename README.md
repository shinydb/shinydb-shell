# shinydb-shell

Interactive command-line interface for shinydb (Yet Another Database).

## Features

- **Management Commands**: Create and manage spaces, stores, indexes, and users
- **YQL Queries**: Execute queries using shinydb Query Language
- **Interactive Shell**: REPL-style interface with command history
- **Connection Options**: Configurable host and port

## Building

```bash
zig build
```

## Running

```bash
# Connect to default server (127.0.0.1:23469)
zig build run

# Connect to custom server
zig build run -- --host 192.168.1.100 --port 23470

# Or run the executable directly
./zig-out/bin/shinydb-cli --host 127.0.0.1 --port 23469
```

## Usage

### Management Commands

```bash
# List entities
.spaces                      # List all spaces
.stores [space]              # List stores (all or in a specific space)
.indexes [store]             # List indexes (all or for a specific store)
.users                       # List all users

# Create entities
.create space <name> [description]
.create store <space.store> [description]
.create index <space.store.index> <field> <String|I32|I64|F64|Boolean>
.create user <username> <password> <0=admin|1=read_write|2=read_only>

# Drop entities
.drop space <name>
.drop store <space.store>
.drop index <space.store.index>
.drop user <username>
```

### YQL Queries

Execute queries directly in the shell:

```bash
# Simple query
test_app.users.limit(10)

# Filtered query
test_app.users.filter(age > 21).limit(5)

# Ordered query
test_app.orders.filter(status = "active").orderBy(created_at, desc).limit(20)

# Complex query
myapp.products.filter(price < 100 and category = "electronics").orderBy(price, asc).limit(50)
```

### Shell Commands

```bash
.help                        # Show help
.exit or .quit              # Exit the shell
.debug <query>              # Parse YQL and show JSON (without executing)
```

## YQL Syntax

```
space.store[.filter(...)][.orderBy(...)][.limit(n)]
space.store[.groupBy(...)][.aggregate(...)]
```

### Filter Operators

- `=` - Equal
- `!=` - Not equal
- `>` - Greater than
- `>=` - Greater than or equal
- `<` - Less than
- `<=` - Less than or equal
- `~` - Regex match
- `in` - In list
- `contains` - Contains value
- `exists` - Field exists

### Aggregation Functions

- `count` - Count documents
- `sum(field)` - Sum values
- `avg(field)` - Average values
- `min(field)` - Minimum value
- `max(field)` - Maximum value

## Examples

```bash
shinydb> .create space myapp "My application"
✓ Created space 'myapp'

shinydb> .create store myapp.users "User data"
✓ Created store 'myapp.users'

shinydb> .create index myapp.users.email_idx email String
✓ Created index 'myapp.users.email_idx' on field 'email' (String)

shinydb> myapp.users.filter(age > 25).orderBy(name, asc).limit(10)
[{"name":"Alice","age":30,"email":"alice@example.com"}]

shinydb> .spaces
Spaces: ["myapp"]

shinydb> .exit
Goodbye!
```

## Dependencies

- shinydb-zig-client: shinydb client library
- proto: Protocol definitions
- bson: BSON encoding/decoding

## License

[Your License Here]
