#!/usr/bin/env python3
"""
Example usage of the Snowflake SQL REST API client.

This script demonstrates various ways to use the snowflake_sql_api module
to query Snowflake data programmatically.
"""

import sys
from pathlib import Path

# Add parent directory to path so we can import the module
sys.path.insert(0, str(Path(__file__).parent.parent))

from snowflake_sql_api import SnowflakeAPI, format_table


def example_basic_query():
    """Simple query example."""
    print("=" * 60)
    print("Example 1: Basic Query")
    print("=" * 60)

    api = SnowflakeAPI()

    result = api.execute("SELECT CURRENT_USER() as user, CURRENT_ROLE() as role")

    print(format_table(result))
    print()


def example_data_query():
    """Query actual data from a table."""
    print("=" * 60)
    print("Example 2: Query Table Data")
    print("=" * 60)

    api = SnowflakeAPI()

    result = api.execute("""
        SELECT
            COUNT(DISTINCT CALL_ID) as total_calls,
            COUNT(DISTINCT CUSTOMER_NAME) as unique_customers,
            MIN(CALL_DATE) as earliest_call,
            MAX(CALL_DATE) as latest_call
        FROM aicollege.public.GONG_CALLS_ENRICHED
        WHERE SPEAKER_NAME LIKE '%Roman Gutin%'
    """)

    print(format_table(result))
    print()


def example_json_output():
    """Get results as JSON."""
    print("=" * 60)
    print("Example 3: JSON Output")
    print("=" * 60)

    api = SnowflakeAPI()

    result = api.execute("SELECT TABLE_NAME FROM aicollege.information_schema.tables WHERE table_schema = 'PUBLIC' LIMIT 5")

    import json
    print(json.dumps(result, indent=2))
    print()


def example_error_handling():
    """Demonstrate error handling."""
    print("=" * 60)
    print("Example 4: Error Handling")
    print("=" * 60)

    api = SnowflakeAPI()

    try:
        result = api.execute("SELECT * FROM nonexistent_table")
    except Exception as e:
        print(f"✅ Caught expected error: {e}")

    print()


def example_async_query():
    """Demonstrate async query execution."""
    print("=" * 60)
    print("Example 5: Async Query")
    print("=" * 60)

    api = SnowflakeAPI()

    # Submit query without waiting
    print("Submitting async query...")
    handle = api.execute_async("SELECT COUNT(*) FROM aicollege.public.GONG_CALLS_ENRICHED")
    print(f"Statement handle: {handle}")

    # Wait a bit
    import time
    time.sleep(3)

    # Check status
    print("Checking status...")
    result = api.get_statement_status(handle)

    if result['success']:
        print("✅ Query completed!")
        print(format_table(result))
    else:
        print("⏳ Query still running...")

    print()


def example_aggregation():
    """More complex aggregation query."""
    print("=" * 60)
    print("Example 6: Aggregation Query")
    print("=" * 60)

    api = SnowflakeAPI()

    result = api.execute("""
        SELECT
            CUSTOMER_NAME,
            COUNT(DISTINCT CALL_ID) as call_count
        FROM aicollege.public.GONG_CALLS_ENRICHED
        WHERE SPEAKER_NAME LIKE '%Roman Gutin%'
        GROUP BY CUSTOMER_NAME
        ORDER BY call_count DESC
        LIMIT 10
    """)

    print(format_table(result))
    print()


def main():
    """Run all examples."""
    print("\n🚀 Snowflake SQL REST API - Example Usage\n")

    try:
        example_basic_query()
        example_data_query()
        example_json_output()
        example_error_handling()
        example_async_query()
        example_aggregation()

        print("=" * 60)
        print("✅ All examples completed successfully!")
        print("=" * 60)

    except Exception as e:
        print(f"\n❌ Error running examples: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
