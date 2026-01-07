#!/usr/bin/env python3
"""
Snowflake SQL REST API Client

This module provides a Python interface to execute SQL queries against Snowflake
using the SQL REST API with OAuth authentication.

Usage:
    from snowflake_sql_api import SnowflakeAPI

    api = SnowflakeAPI()
    result = api.execute("SELECT CURRENT_USER()")
    print(result)

CLI Usage:
    python snowflake_sql_api.py "SELECT CURRENT_USER()"
    python snowflake_sql_api.py "SELECT * FROM mydb.myschema.mytable LIMIT 10"
"""

import os
import sys
import json
import time
import requests
from pathlib import Path
from typing import Optional, Dict, Any, List
from dotenv import load_dotenv


class SnowflakeAPI:
    """Client for Snowflake SQL REST API with OAuth authentication."""

    def __init__(self, env_file: Optional[str] = None):
        """
        Initialize the Snowflake API client.

        Args:
            env_file: Path to .env file. If None, looks in current directory.
        """
        # Load environment variables
        if env_file:
            load_dotenv(env_file)
        else:
            # Try to find .env in script directory
            script_dir = Path(__file__).parent
            env_path = script_dir / '.env'
            if env_path.exists():
                load_dotenv(env_path)
            else:
                load_dotenv()  # Try current directory

        # Read configuration
        self.account_identifier = os.getenv('SNOWFLAKE_ACCOUNT_IDENTIFIER')
        self.oauth_client_id = os.getenv('OAUTH_CLIENT_ID')
        self.oauth_client_secret = os.getenv('OAUTH_CLIENT_SECRET')
        self.refresh_token = os.getenv('OAUTH_REFRESH_TOKEN')
        self.database = os.getenv('MCP_DATABASE', '')
        self.schema = os.getenv('MCP_SCHEMA', '')

        if not all([self.account_identifier, self.oauth_client_id,
                   self.oauth_client_secret, self.refresh_token]):
            raise ValueError(
                "Missing required environment variables. "
                "Ensure .env file has SNOWFLAKE_ACCOUNT_IDENTIFIER, "
                "OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, and OAUTH_REFRESH_TOKEN"
            )

        # Build base URLs
        self.base_url = f"https://{self.account_identifier}.snowflakecomputing.com"
        self.token_url = f"{self.base_url}/oauth/token-request"
        self.sql_url = f"{self.base_url}/api/v2/statements"

        # Cache for access token
        self._access_token: Optional[str] = None
        self._token_expires_at: float = 0

    def _get_access_token(self) -> str:
        """
        Get a valid access token, refreshing if necessary.

        Returns:
            Valid access token
        """
        # Check if we have a valid cached token
        if self._access_token and time.time() < self._token_expires_at:
            return self._access_token

        # Refresh the token
        response = requests.post(
            self.token_url,
            headers={
                'Content-Type': 'application/x-www-form-urlencoded'
            },
            data={
                'grant_type': 'refresh_token',
                'refresh_token': self.refresh_token,
                'client_id': self.oauth_client_id,
                'client_secret': self.oauth_client_secret
            }
        )

        if response.status_code != 200:
            raise Exception(
                f"Failed to refresh token: {response.status_code} - {response.text}"
            )

        token_data = response.json()
        self._access_token = token_data['access_token']
        # Set expiry to 90% of actual expiry to be safe
        expires_in = token_data.get('expires_in', 600)
        self._token_expires_at = time.time() + (expires_in * 0.9)

        return self._access_token

    def execute(
        self,
        sql: str,
        timeout: int = 60,
        database: Optional[str] = None,
        schema: Optional[str] = None,
        warehouse: Optional[str] = None,
        role: Optional[str] = None,
        bindings: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Execute a SQL statement and return the results.

        Args:
            sql: SQL statement to execute
            timeout: Maximum time to wait for results (seconds)
            database: Optional database to use (overrides .env)
            schema: Optional schema to use (overrides .env)
            warehouse: Optional warehouse to use
            role: Optional role to use
            bindings: Optional parameter bindings for prepared statements

        Returns:
            Dictionary containing query results and metadata
        """
        access_token = self._get_access_token()

        # Build request payload
        payload = {
            'statement': sql,
            'timeout': timeout
        }

        if database or self.database:
            payload['database'] = database or self.database
        if schema or self.schema:
            payload['schema'] = schema or self.schema
        if warehouse:
            payload['warehouse'] = warehouse
        if role:
            payload['role'] = role
        if bindings:
            payload['bindings'] = bindings

        # Execute the statement
        response = requests.post(
            self.sql_url,
            headers={
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'User-Agent': 'SnowflakeAPI/1.0',
                'X-Snowflake-Authorization-Token-Type': 'OAUTH'
            },
            json=payload
        )

        if response.status_code not in [200, 202]:
            raise Exception(
                f"SQL execution failed: {response.status_code} - {response.text}"
            )

        result = response.json()

        # If statement is still executing (202), poll for completion
        if response.status_code == 202:
            statement_handle = result['statementHandle']
            result = self._poll_statement(statement_handle, timeout)

        return self._format_result(result)

    def _poll_statement(self, statement_handle: str, timeout: int) -> Dict[str, Any]:
        """
        Poll for statement completion.

        Args:
            statement_handle: Handle returned from statement submission
            timeout: Maximum time to wait (seconds)

        Returns:
            Final statement result
        """
        access_token = self._get_access_token()
        status_url = f"{self.sql_url}/{statement_handle}"

        start_time = time.time()
        while time.time() - start_time < timeout:
            response = requests.get(
                status_url,
                headers={
                    'Authorization': f'Bearer {access_token}',
                    'Accept': 'application/json'
                }
            )

            if response.status_code != 200:
                raise Exception(
                    f"Failed to get statement status: {response.status_code} - {response.text}"
                )

            result = response.json()
            status = result.get('statementStatusUrl')

            # Check if complete
            if 'resultSetMetaData' in result or 'message' in result:
                return result

            # Wait before polling again
            time.sleep(1)

        raise Exception(f"Statement execution timed out after {timeout} seconds")

    def _format_result(self, result: Dict[str, Any]) -> Dict[str, Any]:
        """
        Format the API result into a cleaner structure.

        Args:
            result: Raw API response

        Returns:
            Formatted result dictionary
        """
        formatted = {
            'statement_handle': result.get('statementHandle'),
            'success': 'resultSetMetaData' in result,
            'row_count': 0,
            'columns': [],
            'data': []
        }

        # Extract result set if present
        if 'resultSetMetaData' in result:
            metadata = result['resultSetMetaData']
            formatted['row_count'] = metadata.get('numRows', 0)

            # Extract column names and types
            if 'rowType' in metadata:
                formatted['columns'] = [
                    {
                        'name': col['name'],
                        'type': col['type'],
                        'nullable': col.get('nullable', True)
                    }
                    for col in metadata['rowType']
                ]

            # Extract data rows
            if 'data' in result:
                formatted['data'] = result['data']

        # Include any error messages
        if 'message' in result:
            formatted['message'] = result['message']
        if 'code' in result:
            formatted['code'] = result['code']

        return formatted

    def execute_async(self, sql: str, **kwargs) -> str:
        """
        Submit a SQL statement for asynchronous execution.

        Args:
            sql: SQL statement to execute
            **kwargs: Additional parameters for execute()

        Returns:
            Statement handle for polling
        """
        kwargs['timeout'] = 0  # Don't wait for results
        access_token = self._get_access_token()

        payload = {'statement': sql, 'timeout': 0, 'async': True}

        if kwargs.get('database') or self.database:
            payload['database'] = kwargs.get('database') or self.database
        if kwargs.get('schema') or self.schema:
            payload['schema'] = kwargs.get('schema') or self.schema
        if kwargs.get('warehouse'):
            payload['warehouse'] = kwargs['warehouse']
        if kwargs.get('role'):
            payload['role'] = kwargs['role']

        response = requests.post(
            self.sql_url,
            headers={
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            },
            json=payload
        )

        if response.status_code not in [200, 202]:
            raise Exception(
                f"Async SQL submission failed: {response.status_code} - {response.text}"
            )

        result = response.json()
        return result.get('statementHandle')

    def get_statement_status(self, statement_handle: str) -> Dict[str, Any]:
        """
        Get the status of an asynchronously executed statement.

        Args:
            statement_handle: Handle from execute_async()

        Returns:
            Statement status and results if complete
        """
        access_token = self._get_access_token()
        status_url = f"{self.sql_url}/{statement_handle}"

        response = requests.get(
            status_url,
            headers={
                'Authorization': f'Bearer {access_token}',
                'Accept': 'application/json'
            }
        )

        if response.status_code != 200:
            raise Exception(
                f"Failed to get statement status: {response.status_code} - {response.text}"
            )

        return self._format_result(response.json())

    def cancel_statement(self, statement_handle: str) -> bool:
        """
        Cancel a running statement.

        Args:
            statement_handle: Handle of statement to cancel

        Returns:
            True if cancelled successfully
        """
        access_token = self._get_access_token()
        cancel_url = f"{self.sql_url}/{statement_handle}/cancel"

        response = requests.post(
            cancel_url,
            headers={
                'Authorization': f'Bearer {access_token}',
                'Accept': 'application/json'
            }
        )

        return response.status_code == 200


def format_table(result: Dict[str, Any]) -> str:
    """
    Format query results as an ASCII table.

    Args:
        result: Formatted result from execute()

    Returns:
        ASCII table string
    """
    if not result['success'] or not result['data']:
        return json.dumps(result, indent=2)

    # Get column names
    col_names = [col['name'] for col in result['columns']]

    # Calculate column widths
    widths = [len(name) for name in col_names]
    for row in result['data']:
        for i, val in enumerate(row):
            val_str = str(val) if val is not None else 'NULL'
            widths[i] = max(widths[i], len(val_str))

    # Build table
    lines = []

    # Header
    header = ' | '.join(name.ljust(widths[i]) for i, name in enumerate(col_names))
    lines.append(header)
    lines.append('-' * len(header))

    # Rows
    for row in result['data']:
        row_str = ' | '.join(
            str(val).ljust(widths[i]) if val is not None else 'NULL'.ljust(widths[i])
            for i, val in enumerate(row)
        )
        lines.append(row_str)

    # Footer
    lines.append('')
    lines.append(f"({result['row_count']} rows)")

    return '\n'.join(lines)


def main():
    """CLI interface for Snowflake SQL API."""
    if len(sys.argv) < 2:
        print("Usage: python snowflake_sql_api.py <SQL_QUERY> [--json]")
        print("\nExamples:")
        print('  python snowflake_sql_api.py "SELECT CURRENT_USER()"')
        print('  python snowflake_sql_api.py "SELECT * FROM mytable LIMIT 10"')
        print('  python snowflake_sql_api.py "SHOW TABLES" --json')
        sys.exit(1)

    sql = sys.argv[1]
    output_json = '--json' in sys.argv

    try:
        api = SnowflakeAPI()
        result = api.execute(sql)

        if output_json:
            print(json.dumps(result, indent=2))
        else:
            if result['success']:
                print(format_table(result))
            else:
                print(f"Error: {result.get('message', 'Unknown error')}")
                print(json.dumps(result, indent=2))

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
