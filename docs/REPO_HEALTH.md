# Repo Health Stats Feature Implementation Plan

## Overview

Add a `--health` mode to gh-contrib that collects and tracks repository health metrics over time, stores them in SQLite, and displays trends with ASCII charts.

## Metrics to Collect (per repo)

| Metric | Description |
|--------|-------------|
| open_issues | Total open issues (excluding PRs) |
| open_prs | Total open PRs |
| new_issues | Issues created in the period |
| new_prs | PRs created in the period |
| days_since_release | Days since last non-draft, non-prerelease release (null if none) |
| avg_issue_response_hours | Avg time to first non-author, non-bot comment on open issues |
| avg_pr_response_hours | Avg time to first non-author, non-bot comment OR review on open PRs |
| avg_pr_cycle_hours | Avg time from PR open to merge (for merged PRs in period) |

### Metric Definitions (Precise)

**Response Time Calculation:**
- Measures time from item creation to first qualifying response
- Qualifying response = comment or review from someone who is:
  - NOT the author
  - NOT a bot (detected via `type: Bot`, `[bot]` suffix, or configured ignore list)
- For PRs: includes both issue comments AND review comments/reviews
- Sample: most recent 50 items (deterministic, not random) for performance
- Sample size stored in snapshot for interpretability

**PR Cycle Time:**
- Only includes merged PRs (not closed-without-merge)
- Measures: `merged_at - created_at`
- Period: PRs merged within the week window

**Week Boundaries:**
- Week starts Monday 00:00:00 UTC
- Week ends Sunday 23:59:59 UTC
- Boundaries are inclusive
- `--refresh` mid-week uses UPSERT to update existing snapshot

## CLI Interface

```bash
# Health stats for all repos in an org (default 4 weeks history)
./gh-contrib --health --org crossplane

# Specific repos only
./gh-contrib --health --org crossplane --repos crossplane/crossplane,crossplane/provider-aws

# Extended history
./gh-contrib --health --org crossplane --weeks 8

# Specific metrics only
./gh-contrib --health --org crossplane --health-metrics open-issues,avg-pr-cycle

# Force refresh cached data
./gh-contrib --health --org crossplane --refresh

# Preview API calls without executing (for debugging/rate limit planning)
./gh-contrib --health --org crossplane --dry-run

# Custom ignore list for bot detection
./gh-contrib --health --org crossplane --ignore-users "ci-bot,release-bot"
```

## Database Schema (SQLite at ~/.gh-contrib/health.db)

```sql
-- Schema version for migrations
CREATE TABLE schema_info (
    version INTEGER PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE repos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    github_id INTEGER NOT NULL UNIQUE,      -- GitHub's immutable numeric ID
    node_id TEXT NOT NULL,                  -- GraphQL node ID for future use
    org TEXT NOT NULL,
    name TEXT NOT NULL,
    full_name TEXT NOT NULL,                -- "org/repo" (may change on rename)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE health_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    week_start DATE NOT NULL,               -- Monday YYYY-MM-DD (UTC)
    week_end DATE NOT NULL,                 -- Sunday YYYY-MM-DD (UTC)

    -- Core counts
    open_issues INTEGER NOT NULL,
    open_prs INTEGER NOT NULL,
    new_issues INTEGER NOT NULL,
    new_prs INTEGER NOT NULL,

    -- Release metric
    days_since_release INTEGER,             -- NULL if no releases
    last_release_tag TEXT,                  -- Tag name for reference

    -- Response time metrics (with sample metadata)
    avg_issue_response_hours REAL,          -- NULL if no data
    avg_pr_response_hours REAL,             -- NULL if no data
    issue_response_sample_size INTEGER,     -- How many issues were sampled
    pr_response_sample_size INTEGER,        -- How many PRs were sampled

    -- Cycle time metrics
    avg_pr_cycle_hours REAL,                -- NULL if no merged PRs
    merged_pr_count INTEGER,                -- How many PRs contributed to avg

    -- Audit fields
    collected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (repo_id) REFERENCES repos(id) ON DELETE CASCADE,
    UNIQUE(repo_id, week_start)
);

-- Indexes for efficient queries
CREATE INDEX idx_repos_github_id ON repos(github_id);
CREATE INDEX idx_repos_org ON repos(org);
CREATE INDEX idx_repos_full_name ON repos(full_name);
CREATE INDEX idx_snapshots_repo_week ON health_snapshots(repo_id, week_start);
CREATE INDEX idx_snapshots_week ON health_snapshots(week_start);
```

## API Strategy

### Primary: GraphQL API (for response/cycle time metrics)

Using GraphQL reduces API calls by ~98% compared to REST. A single query can fetch:
- Repository metadata (id, name)
- Open issues with first comments
- Open PRs with first comments and reviews
- Recently merged PRs with timestamps

**Example GraphQL Query:**
```graphql
query RepoHealth($owner: String!, $name: String!, $since: DateTime!) {
  repository(owner: $owner, name: $name) {
    id
    databaseId

    # Open issues count
    openIssues: issues(states: OPEN) { totalCount }

    # Open PRs count
    openPRs: pullRequests(states: OPEN) { totalCount }

    # New issues in period
    newIssues: issues(filterBy: {since: $since}) { totalCount }

    # Sample of open issues for response time (most recent 50)
    issuesSample: issues(states: OPEN, first: 50, orderBy: {field: CREATED_AT, direction: DESC}) {
      nodes {
        createdAt
        author { login }
        comments(first: 10) {
          nodes {
            createdAt
            author { login }
          }
        }
      }
    }

    # Sample of open PRs for response time
    prsSample: pullRequests(states: OPEN, first: 50, orderBy: {field: CREATED_AT, direction: DESC}) {
      nodes {
        createdAt
        author { login }
        comments(first: 10) {
          nodes {
            createdAt
            author { login }
          }
        }
        reviews(first: 10) {
          nodes {
            createdAt
            author { login }
          }
        }
      }
    }

    # Latest release
    latestRelease: releases(first: 1, orderBy: {field: CREATED_AT, direction: DESC}) {
      nodes {
        tagName
        publishedAt
        isDraft
        isPrerelease
      }
    }
  }
}
```

### Fallback: REST API (for counts and search)

| Purpose | Endpoint | Notes |
|---------|----------|-------|
| Repo metadata | `repos/{owner}/{repo}` | Get `id`, `node_id`, `open_issues_count` |
| List org repos | `orgs/{org}/repos?per_page=100` | Paginate for large orgs |
| New issues/PRs | `gh search issues` CLI | Use `is:issue` or `is:pr` explicitly |
| Merged PRs | `search/issues?q=repo:X+is:pr+is:merged+merged:YYYY-MM-DD..YYYY-MM-DD` | For cycle time |
| Latest release | `repos/{owner}/{repo}/releases/latest` | Handle 404 gracefully |

### Rate Limit Strategy

1. **Prefer GraphQL**: 5,000 points/hour, single query for most data
2. **Batch requests**: Collect data for all repos, write to DB in single transaction
3. **Cache aggressively**: Only fetch current week; historical data from SQLite
4. **Conditional requests**: Use ETags where supported
5. **Progress output**: Show rate limit remaining during collection

## Key Implementation Components

### 1. New Constants

```python
HEALTH_METRICS = [
    "open-issues", "open-prs", "new-issues", "new-prs",
    "days-since-release", "avg-issue-response", "avg-pr-response", "avg-pr-cycle"
]
VALID_HEALTH_METRICS = frozenset(HEALTH_METRICS)

# Bot detection patterns
BOT_SUFFIXES = {"[bot]"}
KNOWN_BOTS = frozenset({
    "dependabot", "dependabot-preview", "renovate", "renovate-bot",
    "github-actions", "codecov", "codecov-commenter", "sonarcloud",
    "stale", "mergify", "semantic-release-bot", "greenkeeper"
})

HEALTH_SAMPLE_SIZE = 50  # Items to sample for response time
HEALTH_DB_VERSION = 1
```

### 2. New Dataclasses

```python
@dataclass
class RepoHealthMetrics:
    repo_full_name: str
    github_id: int
    node_id: str
    week_start: datetime
    week_end: datetime

    # Core counts
    open_issues: int
    open_prs: int
    new_issues: int
    new_prs: int

    # Release
    days_since_release: Optional[int]
    last_release_tag: Optional[str]

    # Response times with sample metadata
    avg_issue_response_hours: Optional[float]
    avg_pr_response_hours: Optional[float]
    issue_response_sample_size: int
    pr_response_sample_size: int

    # Cycle time
    avg_pr_cycle_hours: Optional[float]
    merged_pr_count: int
```

### 3. Database Functions

```python
def get_health_db_path() -> Path:
    """Return ~/.gh-contrib/health.db"""

def init_health_db() -> sqlite3.Connection:
    """Initialize DB with schema, handle migrations"""

def get_or_create_repo(conn, github_id, node_id, org, name, full_name) -> int:
    """Get repo by github_id or create new entry. Updates full_name if changed (rename detection)"""

def save_health_snapshot(conn, metrics: RepoHealthMetrics) -> None:
    """UPSERT snapshot (INSERT OR REPLACE on repo_id + week_start)"""

def load_health_snapshots(conn, github_ids: list[int], num_weeks: int) -> dict[int, list[RepoHealthMetrics]]:
    """Load snapshots by github_id for historical queries"""

def get_cached_weeks(conn, github_id: int) -> set[str]:
    """Return set of week_start dates already cached for a repo"""
```

### 4. Data Collection Functions

```python
def list_org_repos(org: str) -> list[dict]:
    """Fetch all repos in org with id, node_id, name, full_name"""

def is_bot_user(username: str, ignore_list: set[str]) -> bool:
    """Check if user is a bot via patterns, known list, or custom ignore list"""

def fetch_repo_health_graphql(repo_full_name: str, since_dt: datetime) -> dict:
    """Single GraphQL query for all health metrics"""

def calculate_response_time(items: list[dict], author_login: str, ignore_users: set[str]) -> Optional[float]:
    """Calculate avg hours to first qualifying response from list of items"""

def collect_repo_health_metrics(
    repo: dict,
    week_start: datetime,
    week_end: datetime,
    ignore_users: set[str]
) -> RepoHealthMetrics:
    """Collect all metrics for one repo for one week"""

def collect_health_for_repos(
    repos: list[dict],
    num_weeks: int,
    ignore_users: set[str],
    refresh: bool = False
) -> dict[str, list[RepoHealthMetrics]]:
    """
    Collect health for multiple repos over multiple weeks.
    - Uses producer-consumer pattern: threads collect, main thread writes to SQLite
    - Only fetches weeks not already in cache (unless refresh=True)
    """
```

### 5. Output Functions

```python
def format_duration(hours: Optional[float]) -> str:
    """Format hours as human-readable: '4.2h', '2.5d', or '-'"""

def render_health_table(metrics_by_repo: dict, week_label: str) -> None:
    """Print markdown table of current health stats"""

def render_health_charts(
    metrics_by_repo: dict,
    selected_metrics: list[str],
    weeks: list[str]
) -> None:
    """Render ASCII trend charts via plotext"""

def run_health_mode(args: argparse.Namespace) -> None:
    """Main orchestration for --health mode"""
```

### 6. Argument Parser Extensions

```python
parser.add_argument("--health", action="store_true",
    help="Enable health stats mode: analyze repository health metrics")
parser.add_argument("--repos", type=str, default=None,
    help="Comma-separated repos (owner/repo). Defaults to all in --org")
parser.add_argument("--health-metrics", type=str, default=None,
    help="Comma-separated metrics to display (default: all)")
parser.add_argument("--dry-run", action="store_true",
    help="Preview API calls without executing")
parser.add_argument("--ignore-users", type=str, default=None,
    help="Comma-separated usernames to treat as bots for response time")
```

## Concurrency Model

**Producer-Consumer Pattern** (avoids SQLite locking issues):

```python
def collect_health_for_repos(repos, num_weeks, ...):
    results_queue = queue.Queue()

    def collect_worker(repo, week_start, week_end):
        metrics = collect_repo_health_metrics(repo, week_start, week_end, ...)
        results_queue.put(metrics)

    # Launch collection threads
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = []
        for repo in repos:
            for week_start, week_end in get_week_boundaries(num_weeks):
                if not is_cached(repo, week_start) or refresh:
                    futures.append(executor.submit(collect_worker, repo, week_start, week_end))

        # Wait for all to complete
        for future in as_completed(futures):
            future.result()  # Raises if collection failed

    # Single-threaded DB writes
    conn = init_health_db()
    while not results_queue.empty():
        metrics = results_queue.get()
        save_health_snapshot(conn, metrics)
    conn.commit()
```

## Implementation Phases

### Phase 1: Database Foundation
- Add `sqlite3` import
- Implement schema creation with version tracking
- Implement CRUD functions with UPSERT pattern
- Handle repo rename detection via `github_id`

### Phase 2: GraphQL Integration
- Implement `gh_graphql()` wrapper function
- Build health query with all needed fields
- Parse response into structured data
- Add `--dry-run` support to preview queries

### Phase 3: Metrics Collection
- Implement `is_bot_user()` with configurable ignore list
- Implement response time calculation (issues + PRs with reviews)
- Implement cycle time calculation for merged PRs
- Add deterministic sampling (most recent N)

### Phase 4: Orchestration
- Implement producer-consumer collection pattern
- Integrate SQLite caching (skip cached weeks unless `--refresh`)
- Add progress output with rate limit info
- Handle errors gracefully (one failing repo doesn't crash batch)

### Phase 5: CLI and Output
- Extend `parse_arguments()` with health flags
- Implement `render_health_table()` with proper formatting
- Implement `render_health_charts()` using plotext
- Update `main()` to route to health mode

### Phase 6: Documentation and Testing
- Update CLAUDE.md with health mode docs
- Add Makefile targets (e.g., `make health-crossplane`)
- Test with real repos across edge cases
- Test repo rename handling

## Output Format Examples

### Current Stats Table
```
## Repository Health (Week of 01/06 - 01/12)

| Repository | Open Issues | Open PRs | New Issues | New PRs | Last Release | Issue Response | PR Response | PR Cycle |
|------------|-------------|----------|------------|---------|--------------|----------------|-------------|----------|
| crossplane/crossplane | 124 | 23 | 5 | 12 | 14d (v1.15.0) | 4.2h (n=50) | 2.1h (n=45) | 36.5h |
| crossplane/provider-aws | 89 | 15 | 3 | 8 | 7d (v0.47.0) | 6.8h (n=50) | 3.4h (n=38) | 48.2h |
| **Total/Avg** | **213** | **38** | **8** | **20** | - | **5.5h** | **2.8h** | **42.4h** |
```

### Trend Charts (via plotext)
One ASCII chart per metric, showing weekly values per repo over the specified weeks.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Repo not found (404) | Log warning, skip repo, continue with others |
| Rate limit hit | Log error with reset time, exit gracefully |
| No releases | Set `days_since_release = NULL`, display as "-" |
| No open issues/PRs | Set response time = NULL, display as "-" |
| Repo renamed | Detect via `github_id`, update `full_name` in DB |
| GraphQL query fails | Fall back to REST endpoints |
| SQLite locked | Should not happen with producer-consumer pattern |

## Critical Files to Modify

- `gh-contrib` - Main script (add all new code)
- `CLAUDE.md` - Add health mode documentation
- `Makefile` - Add health mode targets

## Verification Plan

1. Run `./gh-contrib --health --org <test-org> --dry-run` to preview API calls
2. Run `./gh-contrib --health --org <test-org> --repos <single-repo>` to test basic flow
3. Verify SQLite database created at `~/.gh-contrib/health.db` with correct schema
4. Run again to verify caching works (should skip API calls for cached weeks)
5. Rename a test repo, run again, verify history preserved via `github_id`
6. Run with `--weeks 2` to verify multi-week collection
7. Run with `--health-metrics open-issues,open-prs` to verify metric filtering
8. Run with `--refresh` to verify cache invalidation
9. Run with `--ignore-users "mybot"` to verify custom bot filtering
10. Verify charts render correctly with plotext installed
11. Test with org that has 50+ repos to verify rate limit handling
