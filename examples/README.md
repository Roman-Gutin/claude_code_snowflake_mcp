# Snowflake SQL API Examples

This directory contains example scripts demonstrating how to use the Snowflake SQL REST API client.

## Running the Examples

### Run All Examples
```bash
python3 example_usage.py
```

### Individual Examples in the Script

The `example_usage.py` script demonstrates:

1. **Basic Query** - Simple query to get current user and role
2. **Data Query** - Query actual data with aggregations
3. **JSON Output** - Get results in JSON format
4. **Error Handling** - Proper exception handling
5. **Async Query** - Asynchronous query execution
6. **Aggregation** - Complex aggregation with grouping and sorting

## Creating Your Own Scripts

```python
#!/usr/bin/env python3
import sys
from pathlib import Path

# Add parent directory to import the module
sys.path.insert(0, str(Path(__file__).parent.parent))

from snowflake_sql_api import SnowflakeAPI

# Initialize API
api = SnowflakeAPI()

# Execute query
result = api.execute("SELECT * FROM your_table LIMIT 10")

# Print results
for row in result['data']:
    print(row)
```

## More Examples

### Data Analysis
```python
from snowflake_sql_api import SnowflakeAPI

api = SnowflakeAPI()

# Get call statistics
result = api.execute("""
    SELECT
        DATE_TRUNC('month', CALL_DATE) as month,
        COUNT(*) as call_count,
        COUNT(DISTINCT CUSTOMER_NAME) as unique_customers
    FROM aicollege.public.GONG_CALLS_ENRICHED
    GROUP BY month
    ORDER BY month DESC
""")

for row in result['data']:
    print(f"{row[0]}: {row[1]} calls, {row[2]} customers")
```

### Export to CSV
```python
import csv
from snowflake_sql_api import SnowflakeAPI

api = SnowflakeAPI()
result = api.execute("SELECT * FROM your_table")

# Write to CSV
with open('output.csv', 'w', newline='') as f:
    writer = csv.writer(f)

    # Header
    writer.writerow([col['name'] for col in result['columns']])

    # Data
    writer.writerows(result['data'])
```

### Integration with Pandas
```python
import pandas as pd
from snowflake_sql_api import SnowflakeAPI

api = SnowflakeAPI()
result = api.execute("SELECT * FROM your_table")

# Convert to DataFrame
df = pd.DataFrame(
    result['data'],
    columns=[col['name'] for col in result['columns']]
)

print(df.describe())
```

## See Also

- [SQL API Tool Documentation](../docs/sql-api-tool.md)
- [Main README](../README.md)
