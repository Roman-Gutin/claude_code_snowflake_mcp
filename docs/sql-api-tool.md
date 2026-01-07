# Snowflake SQL REST API Tool

A Python-based tool for executing SQL queries against Snowflake using the SQL REST API with OAuth authentication.

## Features

- OAuth 2.0 authentication with automatic token refresh
- Synchronous and asynchronous query execution
- Statement cancellation support
- Clean JSON and table output formats
- Python module for programmatic use
- Command-line interface for quick queries

## Installation

The tool is already included in your repository. Required dependencies:

```bash
pip3 install requests python-dotenv
```

These are automatically checked and installed when you run `./sf-sql`.

## Usage

### Command Line Interface

#### Basic Query
```bash
./sf-sql "SELECT CURRENT_USER()"
```

#### Query with Table Output (Default)
```bash
./sf-sql "SELECT * FROM aicollege.public.gong_calls_enriched LIMIT 5"
```

#### JSON Output
```bash
./sf-sql "SHOW TABLES IN SCHEMA aicollege.public" --json
```

#### Complex Queries
```bash
./sf-sql "SELECT
    COUNT(DISTINCT CALL_ID) as total_calls,
    COUNT(DISTINCT CUSTOMER_NAME) as unique_customers
FROM aicollege.public.GONG_CALLS_ENRICHED
WHERE SPEAKER_NAME LIKE '%Roman Gutin%'"
```

### Python Module

#### Basic Usage
```python
from snowflake_sql_api import SnowflakeAPI

# Initialize (reads from .env automatically)
api = SnowflakeAPI()

# Execute a query
result = api.execute("SELECT CURRENT_USER()")
print(result)
```

#### Query with Options
```python
result = api.execute(
    "SELECT * FROM mytable WHERE col1 = ?",
    database="AICOLLEGE",
    schema="PUBLIC",
    warehouse="COMPUTE_WH",
    role="AICOLLEGE",
    timeout=120,
    bindings={"1": "value1"}
)

# Access results
print(f"Rows returned: {result['row_count']}")
print(f"Columns: {[col['name'] for col in result['columns']]}")
print(f"Data: {result['data']}")
```

#### Asynchronous Execution
```python
# Submit query without waiting
handle = api.execute_async("SELECT * FROM large_table")
print(f"Statement handle: {handle}")

# Poll for status later
import time
time.sleep(5)

status = api.get_statement_status(handle)
if status['success']:
    print(f"Query complete: {status['row_count']} rows")
    print(status['data'])
else:
    print("Query still running...")
```

#### Cancel Running Statement
```python
handle = api.execute_async("SELECT * FROM very_large_table")

# Cancel if needed
if api.cancel_statement(handle):
    print("Statement cancelled")
```

#### Custom Table Formatting
```python
from snowflake_sql_api import format_table

result = api.execute("SELECT * FROM mytable LIMIT 10")
print(format_table(result))
```

## Result Format

The `execute()` method returns a dictionary with this structure:

```python
{
    'statement_handle': 'unique-statement-id',
    'success': True,
    'row_count': 10,
    'columns': [
        {
            'name': 'COLUMN1',
            'type': 'TEXT',
            'nullable': True
        },
        {
            'name': 'COLUMN2',
            'type': 'NUMBER',
            'nullable': False
        }
    ],
    'data': [
        ['value1', 123],
        ['value2', 456]
    ],
    'message': 'Optional error message',
    'code': 'Optional error code'
}
```

## Configuration

The tool reads configuration from your `.env` file:

```bash
SNOWFLAKE_ACCOUNT_IDENTIFIER=ORGNAME-ACCOUNTNAME
OAUTH_CLIENT_ID=your_client_id
OAUTH_CLIENT_SECRET=your_client_secret
OAUTH_REFRESH_TOKEN=your_refresh_token
MCP_DATABASE=aicollege       # Default database (optional)
MCP_SCHEMA=public            # Default schema (optional)
```

## Advanced Examples

### Data Analysis Script
```python
#!/usr/bin/env python3
from snowflake_sql_api import SnowflakeAPI
import pandas as pd

api = SnowflakeAPI()

# Get call data
result = api.execute("""
    SELECT
        CALL_DATE,
        CUSTOMER_NAME,
        SPEAKER_NAME,
        INTENT
    FROM aicollege.public.GONG_CALLS_ENRICHED
    WHERE CALL_DATE >= CURRENT_DATE - 30
""")

# Convert to pandas DataFrame
df = pd.DataFrame(result['data'], columns=[col['name'] for col in result['columns']])

# Analyze
print(f"Total calls in last 30 days: {len(df)}")
print(f"\nTop customers:\n{df['CUSTOMER_NAME'].value_counts().head(10)}")
```

### Batch Processing
```python
from snowflake_sql_api import SnowflakeAPI

api = SnowflakeAPI()

# Submit multiple queries asynchronously
handles = []
queries = [
    "SELECT COUNT(*) FROM table1",
    "SELECT COUNT(*) FROM table2",
    "SELECT COUNT(*) FROM table3"
]

for query in queries:
    handle = api.execute_async(query)
    handles.append((handle, query))

# Wait and collect results
import time
time.sleep(10)

for handle, query in handles:
    result = api.get_statement_status(handle)
    if result['success']:
        print(f"{query}: {result['data'][0][0]} rows")
```

### ETL Pipeline
```python
from snowflake_sql_api import SnowflakeAPI

api = SnowflakeAPI()

# Create staging table
api.execute("""
    CREATE OR REPLACE TABLE staging.processed_calls AS
    SELECT
        CALL_ID,
        CUSTOMER_NAME,
        CALL_DATE,
        COUNT(*) as snippet_count
    FROM aicollege.public.GONG_CALLS_ENRICHED
    GROUP BY CALL_ID, CUSTOMER_NAME, CALL_DATE
""")

# Verify
result = api.execute("SELECT COUNT(*) FROM staging.processed_calls")
print(f"Processed {result['data'][0][0]} calls")
```

## Error Handling

```python
from snowflake_sql_api import SnowflakeAPI

api = SnowflakeAPI()

try:
    result = api.execute("SELECT * FROM nonexistent_table")
except Exception as e:
    print(f"Query failed: {e}")
```

## Performance Tips

1. **Use specific columns** instead of `SELECT *` for better performance
2. **Add LIMIT clauses** when exploring data
3. **Use async execution** for long-running queries
4. **Reuse the API instance** - it caches access tokens
5. **Specify database and schema** in queries to avoid connection overhead

## Comparison with Other Tools

| Feature | SQL REST API | MCP Tool | Direct JDBC |
|---------|-------------|----------|-------------|
| OAuth Support | ✅ | ✅ | ⚠️ Complex |
| Async Execution | ✅ | ❌ | ✅ |
| Easy CLI | ✅ | ❌ | ❌ |
| Python Module | ✅ | ⚠️ Indirect | ✅ |
| No Binary Deps | ✅ | ✅ | ❌ |
| Statement Cancel | ✅ | ❌ | ✅ |

## Troubleshooting

### Token Errors
```
Error: Failed to refresh token: 401
```
**Solution:** Your refresh token may have expired. Re-run the OAuth flow:
```bash
./setup.sh oauth
```

### Missing Environment Variables
```
ValueError: Missing required environment variables
```
**Solution:** Ensure your `.env` file exists and has all required fields:
```bash
cat .env
```

### Connection Timeout
```
Statement execution timed out
```
**Solution:** Increase timeout or use async execution:
```python
result = api.execute(sql, timeout=300)  # 5 minutes
```

### SSL Certificate Errors
```
SSLError: certificate verify failed
```
**Solution:** Update your Python certificates:
```bash
pip3 install --upgrade certifi
```

## API Reference

### SnowflakeAPI Class

#### `__init__(env_file: Optional[str] = None)`
Initialize the API client with configuration from .env file.

#### `execute(sql: str, timeout: int = 60, **kwargs) -> Dict[str, Any]`
Execute a SQL statement synchronously and return results.

**Parameters:**
- `sql`: SQL statement to execute
- `timeout`: Maximum wait time in seconds (default: 60)
- `database`: Override default database
- `schema`: Override default schema
- `warehouse`: Specify warehouse to use
- `role`: Specify role to use
- `bindings`: Parameter bindings for prepared statements

**Returns:** Formatted result dictionary

#### `execute_async(sql: str, **kwargs) -> str`
Submit SQL for async execution without waiting.

**Returns:** Statement handle for polling

#### `get_statement_status(statement_handle: str) -> Dict[str, Any]`
Check status of async statement.

**Returns:** Status and results if complete

#### `cancel_statement(statement_handle: str) -> bool`
Cancel a running statement.

**Returns:** True if successfully cancelled

### Helper Functions

#### `format_table(result: Dict[str, Any]) -> str`
Format query results as ASCII table.

## Files

- `snowflake_sql_api.py` - Python module with full API
- `sf-sql` - Shell wrapper for CLI usage

## See Also

- [Snowflake SQL REST API Documentation](https://docs.snowflake.com/en/developer-guide/sql-api/index.html)
- [Main README](../README.md)
- [Troubleshooting Guide](troubleshooting.md)
