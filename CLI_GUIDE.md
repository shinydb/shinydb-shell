# shinydb CLI Guide

An interactive command-line interface for ShinyDb with unified management API and YQL query support.

## Table of Contents

- [Getting Started](#getting-started)
- [Interactive Shell](#interactive-shell)
- [Management Commands](#management-commands)
- [YQL Query Language](#yql-query-language)
- [User Management](#user-management)
- [Common Workflows](#common-workflows)
- [Troubleshooting](#troubleshooting)

---

## Getting Started

### Installation

```bash
cd /path/to/shinydb-cli
zig build
```

The compiled binary will be at `zig-out/bin/shinydb-cli`.

### Starting the CLI

```bash
# Connect to default server (127.0.0.1:23469)
shinydb-cli

# Connect to custom server
shinydb-cli --host 192.168.1.100 --port 23470

# Show help
shinydb-cli --help
```

### Command-Line Options

| Option          | Description           | Default   |
| --------------- | --------------------- | --------- |
| `--host <HOST>` | Server hostname or IP | 127.0.0.1 |
| `--port <PORT>` | Server port           | 23469     |
| `--help`, `-h`  | Show help message     |           |

---

## Interactive Shell

The CLI provides an interactive REPL (Read-Eval-Print Loop) shell for working with shinydb.

### Shell Prompt

```
shinydb>
```

### Shell Commands

All commands start with a dot (`.`):

| Command                 | Description                                       |
| ----------------------- | ------------------------------------------------- |
| `.help`                 | Show detailed help                                |
| `.exit`, `.quit`        | Exit the shell                                    |
| `.spaces`               | List all spaces                                   |
| `.stores [space]`       | List stores (all or in specific space)            |
| `.indexes [store]`      | List indexes (all or for specific store)          |
| `.users`                | List all users                                    |
| `.create <type> <args>` | Create entities (space, store, index, user)       |
| `.drop <type> <name>`   | Drop entities (space, store, index, user)         |
| `.debug <query>`        | Parse YQL query and show JSON (without executing) |

### Executing YQL Queries

Type YQL queries directly at the prompt (no command prefix needed):

```
shinydb> myapp.users.limit(10)
shinydb> myapp.orders.filter(status = "active").orderBy(created_at, desc)
```

---

## Management Commands

### Spaces

#### List All Spaces

```
shinydb> .spaces
```

**Output:**

```
Spaces: ["myapp","sales","analytics"]
```

#### Create a Space

```
shinydb> .create space <name> [description]
```

**Examples:**

```
shinydb> .create space myapp
shinydb> .create space analytics "Analytics data warehouse"
```

**Output:**

```
✓ Created space 'myapp'
```

#### Drop a Space

```
shinydb> .drop space <name>
```

**Example:**

```
shinydb> .drop space myapp
```

**Output:**

```
✓ Dropped space 'myapp'
```

**Warning:** This deletes the space and ALL its stores and data!

---

### Stores

#### List Stores

```
shinydb> .stores              # List all stores
shinydb> .stores <space>      # List stores in specific space
```

**Examples:**

```
shinydb> .stores
All stores: ["myapp.users","myapp.orders","sales.orders"]

shinydb> .stores myapp
Stores in 'myapp': ["myapp.users","myapp.orders"]
```

#### Create a Store

```
shinydb> .create store <space.store> [description]
```

**Examples:**

```
shinydb> .create store myapp.users
shinydb> .create store myapp.orders "Order tracking"
```

**Output:**

```
✓ Created store 'myapp.users'
```

**Note:** If the parent space doesn't exist, it will be auto-created.

#### Drop a Store

```
shinydb> .drop store <space.store>
```

**Example:**

```
shinydb> .drop store myapp.users
```

**Output:**

```
✓ Dropped store 'myapp.users'
```

---

### Indexes

#### List Indexes

```
shinydb> .indexes                    # List all indexes
shinydb> .indexes <space.store>      # List indexes for specific store
```

**Examples:**

```
shinydb> .indexes
All indexes: ["myapp.users.email_idx","myapp.users.age_idx"]

shinydb> .indexes myapp.users
Indexes for 'myapp.users': ["myapp.users.email_idx","myapp.users.age_idx"]
```

#### Create an Index

```
shinydb> .create index <space.store.index> <field> <type>
```

**Field Types:**

- `String` - Text field
- `I32` - 32-bit signed integer
- `I64` - 64-bit signed integer
- `F64` - 64-bit floating point
- `Boolean` - Boolean value

**Examples:**

```
shinydb> .create index myapp.users.email_idx email String
✓ Created index 'myapp.users.email_idx' on field 'email' (String)

shinydb> .create index myapp.users.age_idx age I32
✓ Created index 'myapp.users.age_idx' on field 'age' (I32)

shinydb> .create index myapp.products.price_idx price F64
✓ Created index 'myapp.products.price_idx' on field 'price' (F64)
```

#### Drop an Index

```
shinydb> .drop index <space.store.index>
```

**Example:**

```
shinydb> .drop index myapp.users.email_idx
✓ Dropped index 'myapp.users.email_idx'
```

---

## YQL Query Language

YQL (shinydb Query Language) provides a fluent, chainable syntax for querying documents.

### Basic Syntax

```
space.store[.operation(...)][.operation(...)]...
```

### Query Operations

| Operation              | Description                   | Example                      |
| ---------------------- | ----------------------------- | ---------------------------- |
| `.filter(condition)`   | Filter documents by condition | `.filter(age > 21)`          |
| `.orderBy(field, dir)` | Sort results (asc or desc)    | `.orderBy(created_at, desc)` |
| `.limit(n)`            | Limit number of results       | `.limit(10)`                 |
| `.skip(n)`             | Skip first N results          | `.skip(20)`                  |

### Filter Operators

| Operator   | Description           | Example                           |
| ---------- | --------------------- | --------------------------------- |
| `=`        | Equal                 | `status = "active"`               |
| `!=`       | Not equal             | `status != "deleted"`             |
| `>`        | Greater than          | `age > 21`                        |
| `>=`       | Greater than or equal | `age >= 18`                       |
| `<`        | Less than             | `price < 100`                     |
| `<=`       | Less than or equal    | `price <= 50`                     |
| `~`        | Regex match           | `name ~ "^John"`                  |
| `in`       | Value in list         | `status in ["active", "pending"]` |
| `contains` | Array/string contains | `tags contains "featured"`        |
| `exists`   | Field exists          | `email exists`                    |

### Logical Operators

Combine conditions with `and` / `or`:

```
shinydb> myapp.users.filter(age > 21 and status = "active")
shinydb> myapp.orders.filter(status = "pending" or status = "processing")
```

### Query Examples

#### Simple Queries

```
# Get first 10 users
shinydb> myapp.users.limit(10)

# Filter by field value
shinydb> myapp.users.filter(age > 25)

# String equality
shinydb> myapp.users.filter(name = "Alice")

# Range query
shinydb> myapp.orders.filter(total > 50 and total < 200)

# Sorted results
shinydb> myapp.orders.orderBy(created_at, desc).limit(20)

# Pagination
shinydb> myapp.users.orderBy(name, asc).skip(20).limit(10)
```

#### Complex Queries

```
# Active orders over $100, sorted by date
shinydb> myapp.orders.filter(status = "active" and total > 100).orderBy(order_date, desc)

# Recent high-value orders
shinydb> myapp.orders.filter(total > 500).orderBy(created_at, desc).limit(5)

# Users in specific age range
shinydb> myapp.users.filter(age >= 18 and age <= 65).limit(50)
```

### Aggregation Operations

| Operation                       | Description         | Example                                          |
| ------------------------------- | ------------------- | ------------------------------------------------ |
| `.groupBy(field1, field2, ...)` | Group by fields     | `.groupBy(category)`                             |
| `.aggregate(name: func, ...)`   | Define aggregations | `.aggregate(total: count, revenue: sum(amount))` |

### Aggregation Functions

| Function     | Description       | Example                 |
| ------------ | ----------------- | ----------------------- |
| `count`      | Count documents   | `total: count`          |
| `sum(field)` | Sum numeric field | `revenue: sum(amount)`  |
| `avg(field)` | Average of field  | `avg_price: avg(price)` |
| `min(field)` | Minimum value     | `lowest: min(price)`    |
| `max(field)` | Maximum value     | `highest: max(price)`   |

### Aggregation Examples

```
# Count all orders
shinydb> myapp.orders.aggregate(total: count)

# Sum of a field
shinydb> myapp.orders.filter(status = "completed").aggregate(revenue: sum(amount))

# Multiple aggregations
shinydb> myapp.orders.aggregate(count: count, total: sum(amount), avg: avg(amount))

# Group by single field
shinydb> myapp.orders.groupBy(category).aggregate(count: count, total: sum(amount))

# Group by multiple fields
shinydb> myapp.sales.groupBy(region, year).aggregate(orders: count, revenue: sum(amount))

# Filter, group, and aggregate
shinydb> myapp.orders.filter(status = "completed").groupBy(customer_id).aggregate(orders: count, spent: sum(total))
```

### Debug Mode

Use `.debug` to see the parsed query without executing it:

```
shinydb> .debug myapp.users.filter(age > 21).limit(10)
Input: myapp.users.filter(age > 21).limit(10)
Parsed:
  Space: myapp
  Store: users
  Filters: 1
  Limit: 10
JSON: {"filter":{"age":{"$gt":21}},"limit":10}
```

This is useful for:

- Understanding how YQL is translated to JSON
- Debugging complex queries
- Learning the query syntax

---

## User Management

**Note:** User management requires admin privileges.

### List Users

```
shinydb> .users
```

**Output:**

```
Users: ["admin","alice","bob"]
```

### Create a User

```
shinydb> .create user <username> <password> <role>
```

**Roles:**

- `0` - admin (full access including user management)
- `1` - read_write (read and write data, manage schema)
- `2` - read_only (read-only access)

**Examples:**

```
shinydb> .create user alice secretpass 1
✓ Created user 'alice' with role 'read_write'

shinydb> .create user bob viewerpass 2
✓ Created user 'bob' with role 'read_only'

shinydb> .create user superadmin adminpass 0
✓ Created user 'superadmin' with role 'admin'
```

### Drop a User

```
shinydb> .drop user <username>
```

**Example:**

```
shinydb> .drop user alice
✓ Dropped user 'alice'
```

---

## Common Workflows

### Setting Up a New Application

```
shinydb> .create space myapp "My application"
shinydb> .create store myapp.users "User accounts"
shinydb> .create store myapp.orders "Order tracking"
shinydb> .create store myapp.products "Product catalog"
shinydb> .create index myapp.users.email_idx email String
shinydb> .create index myapp.orders.status_idx status String
shinydb> .create index myapp.products.category_idx category String
```

### Querying Application Data

```
# Get recent orders
shinydb> myapp.orders.orderBy(created_at, desc).limit(20)

# Find active users
shinydb> myapp.users.filter(status = "active").limit(50)

# High-value completed orders
shinydb> myapp.orders.filter(status = "completed" and total > 500)

# Products in category
shinydb> myapp.products.filter(category = "electronics").limit(100)
```

### Analytics Queries

```
# Count users by status
shinydb> myapp.users.groupBy(status).aggregate(count: count)

# Revenue by month
shinydb> myapp.orders.groupBy(month).aggregate(orders: count, revenue: sum(total))

# Average order value by customer
shinydb> myapp.orders.groupBy(customer_id).aggregate(orders: count, avg_value: avg(total))

# Sales statistics
shinydb> myapp.orders.filter(status = "completed").aggregate(
  total_orders: count,
  revenue: sum(total),
  avg_order: avg(total),
  min_order: min(total),
  max_order: max(total)
)
```

### User Administration

```
# Create application users
shinydb> .create user app_service servicepass123 1
shinydb> .create user readonly_viewer viewpass456 2

# List all users
shinydb> .users

# Remove old users
shinydb> .drop user old_user
```

### Cleanup Operations

```
# Drop test data
shinydb> .drop store test_space.test_store
shinydb> .drop space test_space

# Remove unused indexes
shinydb> .drop index myapp.users.old_index
```

---

## Troubleshooting

### Connection Issues

**Problem:** Cannot connect to server

**Solutions:**

```bash
# Verify server is running
# Check server logs

# Try connecting with explicit host/port
shinydb-cli --host 127.0.0.1 --port 23469

# Check firewall rules
# Verify network connectivity
```

### Authentication Errors

**Problem:** Unauthenticated or permission denied

**Solution:** The CLI automatically attempts to authenticate as admin. If you get authentication errors, verify the server's admin credentials are set correctly.

### Command Not Recognized

**Problem:** "Unknown command" error

**Possible causes:**

- Missing dot prefix for management commands (use `.spaces` not `spaces`)
- Typo in command name
- Invalid YQL syntax

**Check:**

```
shinydb> .help     # View all available commands
```

### Query Returns Empty Results

**Problem:** Query returns `[]` but you expect data

**Debug steps:**

```
# Verify the store has data
shinydb> myapp.users.limit(10)

# Check store name is correct
shinydb> .stores myapp

# Use .debug to see parsed query
shinydb> .debug myapp.users.filter(age > 21)
```

### Performance Issues

**Problem:** Slow queries

**Solutions:**

- Create indexes on frequently queried fields
- Use `.limit()` to reduce result set size
- Add filters to reduce documents scanned
- Consider using aggregations for summary data

**Example optimization:**

```
# Slow: scan all documents
shinydb> myapp.orders.filter(status = "completed")

# Faster: create index first
shinydb> .create index myapp.orders.status_idx status String

# Then query will use the index
shinydb> myapp.orders.filter(status = "completed")
```

---

## Best Practices

### Schema Design

1. **Organize with spaces** - Use spaces to separate different applications or environments

   ```
   prod_app.users
   staging_app.users
   dev_app.users
   ```

2. **Name stores clearly** - Use descriptive names that indicate the data type

   ```
   myapp.user_accounts
   myapp.customer_orders
   myapp.product_catalog
   ```

3. **Create indexes strategically** - Index fields you frequently filter/sort by
   ```
   .create index myapp.users.email_idx email String
   .create index myapp.orders.status_idx status String
   .create index myapp.orders.date_idx created_at I64
   ```

### Query Optimization

1. **Use filters early** - Apply filters before sorting or limiting

   ```
   # Good
   myapp.orders.filter(status = "active").orderBy(date, desc).limit(10)

   # Less efficient
   myapp.orders.orderBy(date, desc).limit(10).filter(status = "active")
   ```

2. **Limit result sets** - Always use `.limit()` for large datasets

   ```
   myapp.users.limit(100)  # Better than returning all users
   ```

3. **Use aggregations for counts** - Don't fetch all documents just to count

   ```
   # Good - aggregation
   myapp.orders.aggregate(total: count)

   # Bad - fetching all documents
   myapp.orders.limit(999999)  # Then counting client-side
   ```

### Security

1. **Use appropriate roles** - Don't give all users admin access

   ```
   .create user app_readonly readpass 2    # Read-only for reporting
   .create user app_service servicepass 1   # Read-write for app
   .create user dba adminpass 0             # Admin only for DBAs
   ```

2. **Rotate passwords** - Change passwords periodically (use server's password reset)

3. **Monitor user list** - Regularly check and remove unused accounts
   ```
   .users
   .drop user old_unused_account
   ```

---

## Tips and Tricks

### Shell History

The shell maintains command history. Use up/down arrow keys to navigate previous commands.

### Multi-line Queries

For complex queries, you can chain multiple operations:

```
shinydb> myapp.orders
  .filter(status = "completed" and total > 100)
  .orderBy(created_at, desc)
  .groupBy(customer_id)
  .aggregate(orders: count, spent: sum(total))
```

### Quick Data Exploration

```
# See what spaces exist
shinydb> .spaces

# Check what stores are in a space
shinydb> .stores myapp

# Peek at data structure
shinydb> myapp.users.limit(1)

# See what indexes are available
shinydb> .indexes myapp.users
```

### Development Workflow

```
# 1. Set up schema
shinydb> .create space dev_app
shinydb> .create store dev_app.test_data

# 2. Test queries
shinydb> dev_app.test_data.limit(10)
shinydb> .debug dev_app.test_data.filter(status = "active")

# 3. Create indexes as needed
shinydb> .create index dev_app.test_data.status_idx status String

# 4. Clean up
shinydb> .drop space dev_app
```

---

## Getting Help

### In the Shell

```
shinydb> .help     # Show comprehensive help
```

### Command-Line

```bash
shinydb-cli --help
```

### Documentation

- **README**: Project overview and quick start
- **CLI_GUIDE**: This comprehensive guide (you're reading it!)
- **shinydb Docs**: Full database documentation

### Reporting Issues

If you encounter bugs or have feature requests:

1. Check existing issues at the project repository
2. Provide clear reproduction steps
3. Include CLI version and server version
4. Share error messages and logs

---

## Appendix

### YQL Grammar Reference

```
query          := namespace [operation]*
namespace      := IDENTIFIER "." IDENTIFIER
operation      := filter_op | sort_op | limit_op | skip_op | group_op | aggregate_op
filter_op      := ".filter(" condition ")"
condition      := expression | condition AND condition | condition OR condition
expression     := field operator value
operator       := "=" | "!=" | ">" | ">=" | "<" | "<=" | "~" | "in" | "contains" | "exists"
sort_op        := ".orderBy(" field "," direction ")"
direction      := "asc" | "desc"
limit_op       := ".limit(" NUMBER ")"
skip_op        := ".skip(" NUMBER ")"
group_op       := ".groupBy(" field ["," field]* ")"
aggregate_op   := ".aggregate(" agg_spec ["," agg_spec]* ")"
agg_spec       := IDENTIFIER ":" agg_func
agg_func       := "count" | "sum(" field ")" | "avg(" field ")" | "min(" field ")" | "max(" field ")"
field          := IDENTIFIER
value          := STRING | NUMBER | BOOLEAN | "[" value ["," value]* "]"
```

### Field Type Reference

| Type      | Description           | Example Values                  | Use Cases                         |
| --------- | --------------------- | ------------------------------- | --------------------------------- |
| `String`  | Text data             | `"John"`, `"alice@example.com"` | Names, emails, descriptions       |
| `I32`     | 32-bit signed integer | `-2147483648` to `2147483647`   | Ages, small counts, IDs           |
| `I64`     | 64-bit signed integer | Large integers                  | Timestamps, large IDs             |
| `F64`     | 64-bit float          | `3.14`, `-99.99`, `1.5e10`      | Prices, measurements, percentages |
| `Boolean` | True/false            | `true`, `false`                 | Flags, status indicators          |

### Status Codes

The server returns various status codes in responses:

| Code | Meaning           | Description                         |
| ---- | ----------------- | ----------------------------------- |
| 200  | OK                | Operation succeeded                 |
| 400  | Bad Request       | Invalid query syntax or parameters  |
| 401  | Unauthenticated   | Not logged in or session expired    |
| 403  | Permission Denied | Insufficient privileges             |
| 404  | Not Found         | Space, store, or document not found |
| 500  | Server Error      | Internal server error               |

---

**Version:** 0.1.0
**Last Updated:** February 2026
**shinydb CLI** - Built with ❤️ using Zig
