# Code Review: gh-contrib

## Summary
The code is well-structured and functional, but there are several opportunities to make it more idiomatic Python.

## High Priority Issues

### 1. Magic Numbers and Strings Should Be Constants
**Location**: Throughout the file
**Issue**: Hard-coded values scattered through the code
**Fix**: Define module-level constants

```python
# Current
cmd = [..., "--limit", "200"]
with ThreadPoolExecutor(max_workers=10) as executor:
if len(title) > 60:

# Recommended
SEARCH_LIMIT = 200
MAX_WORKERS = 10
TITLE_TRUNCATE_LENGTH = 60
API_PAGE_SIZE = 100
PASSIVE_INTERACTION_TYPES = frozenset({"review-requested", "assignee", "mentioned"})
```

### 2. Repeated Logic Should Be Extracted
**Location**: Lines 162, 92, 387
**Issue**: PR detection logic repeated 3 times
**Fix**: Extract to helper function

```python
def is_pull_request(item: dict) -> bool:
    """Determine if an item is a pull request."""
    return (
        item.get("isPullRequest", False)
        or item["state"] == "MERGED"
        or "/pull/" in item["url"]
    )
```

### 3. Nested Function Should Be Module-Level
**Location**: Line 265
**Issue**: `process_item_for_users` defined inside `main()`
**Fix**: Move to module level for better testability and reusability

### 4. Username Parsing Logic Duplicated
**Location**: Lines 304, 354, 391-393
**Issue**: Same parsing logic repeated multiple times
**Fix**: Extract to helper function

```python
def parse_interaction(interaction: str, default_username: Optional[str] = None) -> tuple[str, Optional[str]]:
    """Parse interaction string into base type and username.

    Args:
        interaction: String like "author (@username)" or "author"
        default_username: Username to use if not tagged

    Returns:
        Tuple of (base_interaction, username)
    """
    if " (@" in interaction:
        base = interaction.split(" (@")[0]
        username = interaction.split(" (@")[1].rstrip(")")
        return base, username
    return interaction, default_username
```

### 5. Grouping by Repository Logic Duplicated
**Location**: Lines 319-324, 364-369, 467-472
**Issue**: Identical dictionary grouping pattern repeated 3 times
**Fix**: Extract to helper function

```python
from collections import defaultdict

def group_by_repository(items: list[dict]) -> dict[str, list[dict]]:
    """Group items by repository name."""
    by_repo = defaultdict(list)
    for item in items:
        repo_name = item["repository"]["name"]
        by_repo[repo_name].append(item)
    return dict(by_repo)
```

## Medium Priority Issues

### 6. Use dataclasses for Structured Data
**Location**: Lines 383-409
**Issue**: Using plain dicts with string keys is not type-safe
**Fix**: Use dataclass

```python
from dataclasses import dataclass, field

@dataclass
class UserStats:
    prs_authored: int = 0
    prs_reviewed: int = 0
    prs_commented: int = 0
    issues_authored: int = 0
    issues_commented: int = 0

    def total(self) -> int:
        return sum([
            self.prs_authored,
            self.prs_reviewed,
            self.prs_commented,
            self.issues_authored,
            self.issues_commented
        ])
```

### 7. Column Width Calculation is Repetitive
**Location**: Lines 441-446
**Issue**: Verbose column width calculation
**Fix**: Use more concise approach

```python
# Calculate column widths
col_widths = [len(h) for h in headers]
for username, stats in sorted_users:
    values = [username, *[str(v) for v in stats.values()]]
    col_widths = [max(cw, len(val)) for cw, val in zip(col_widths, values)]
```

### 8. Missing Type Hints
**Location**: Line 173
**Issue**: `main()` lacks return type annotation
**Fix**: Add `-> None`

```python
def main() -> None:
    """Main entry point for the script."""
```

### 9. Use Walrus Operator
**Location**: Lines 70-75
**Issue**: Could be more concise
**Fix**: Use walrus operator

```python
# Current
created_at = item.get("createdAt")
if created_at:
    created_dt = parse_datetime(created_at)

# Recommended
if created_at := item.get("createdAt"):
    created_dt = parse_datetime(created_at)
```

### 10. Outdated Docstring
**Location**: Line 8
**Issue**: References old filename
**Fix**: Update to current filename

```python
"""
Fetch GitHub issues and PRs a user has interacted with in a given organization.

Uses the gh CLI for authentication.

Usage:
    ./gh-contrib --username <username> --org <org> [--days <days>]

Requirements:
    - gh CLI installed and authenticated (https://cli.github.com/)
"""
```

## Low Priority Issues

### 11. Use More Specific Type Hints
**Issue**: Generic `dict` and `list` types could be more specific
**Fix**: Use `dict[str, Any]` or TypedDict

```python
from typing import Any, TypedDict

class GitHubItem(TypedDict):
    url: str
    title: str
    state: str
    repository: dict[str, Any]
    # ... other fields
```

### 12. String Formatting Consistency
**Location**: Line 458
**Issue**: Very long f-string is hard to read
**Fix**: Break into multiple lines or use format

```python
# Current
row = f"| {username.ljust(col_widths[0])} | {str(stats['prs_authored']).ljust(col_widths[1])} | ..."

# Recommended
values = [
    username,
    str(stats['prs_authored']),
    str(stats['prs_reviewed']),
    str(stats['prs_commented']),
    str(stats['issues_authored']),
    str(stats['issues_commented'])
]
row = "| " + " | ".join(v.ljust(w) for v, w in zip(values, col_widths)) + " |"
```

### 13. Use frozenset for Immutable Sets
**Location**: Line 295
**Issue**: Set that never changes should be frozenset
**Fix**: Use `frozenset` or define as module constant

### 14. Better Variable Names
**Location**: Lines 139-140
**Issue**: `latest1`, `latest2` not descriptive
**Fix**: Use descriptive names

```python
# Current
latest1 = ...
latest2 = ...

# Recommended
latest_basic_interaction = ...
latest_additional_interaction = ...
```

### 15. Error Handling Could Be More Specific
**Location**: Line 49
**Issue**: Silent failure returns None
**Consideration**: Log the error or provide more context

```python
except subprocess.CalledProcessError as e:
    # Log the error if needed
    return None
```

## Additional Suggestions

### 16. Consider Using a GitHub Library
Instead of shelling out to `gh`, consider using PyGithub or similar for better error handling and type safety.

### 17. Add Logging
Replace `print` statements with proper logging for better control over output verbosity.

### 18. Configuration File Support
Consider supporting a config file (YAML/TOML) for commonly used options.

## Conclusion

The code is functional and well-organized. The main improvements would be:
1. Extract constants and repeated logic
2. Use dataclasses for structured data
3. Move nested function to module level
4. Add more specific type hints
5. Improve error handling and logging

These changes would make the code more maintainable, testable, and idiomatic Python.
