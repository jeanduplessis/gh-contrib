# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains `gh-contrib`, an executable Python script that fetches and analyzes GitHub activity for users within organizations. It uses the GitHub CLI (`gh`) for authentication and API access, displaying issues and PRs where specified users have actively participated.

## Requirements

- Python 3.14+
- GitHub CLI (`gh`) must be installed and authenticated (https://cli.github.com/)
- No external Python dependencies beyond standard library

## Running the Script

Basic usage:
```bash
./gh-contrib --username <username> --org <org>
```

Common options:
```bash
# Search last 7 days (default)
./gh-contrib -u username -o myorg

# Custom date range
./gh-contrib -u username -o myorg --days 14
./gh-contrib -u username -o myorg --end-date 2024-12-01 --days 7

# Last complete week (Monday-Sunday)
./gh-contrib -u username -o myorg --last-week

# Multiple users/orgs (comma-separated)
./gh-contrib -u user1,user2 -o org1,org2

# Show filtered items
./gh-contrib -u username -o myorg --show-filtered
```

## Using Makefile Shortcuts

The repository includes a Makefile with predefined commands:
```bash
# Show available commands
make help

# Run predefined team activity report
make control-planes-last-week
```

## Code Architecture

### Core Workflow

1. **Search Phase**: Uses `gh search issues --involves <user>` to get candidate issues/PRs
2. **Enrichment Phase**: Parallel processing fetches detailed interaction data via GitHub API
3. **Filtering Phase**: Filters out passive-only interactions (review-requested, assignee, mentioned)
4. **Display Phase**: Groups results by repository and formats as markdown tables

### Key Functions

- `gh_search()`: Wrapper around `gh search issues` CLI command
- `gh_api()`: Wrapper around `gh api` for detailed API calls
- `get_interaction_details()`: Extracts basic interactions (author, assignee) from search results
- `fetch_additional_interactions()`: Makes API calls to fetch comments and reviews with timestamps
- `process_item()`: Combines basic and additional interactions, tracks latest interaction timestamp
- `process_item_for_users()`: Handles multiple users, tags interactions per user

### Interaction Types

The script categorizes interactions as:
- **Active**: author, commenter, reviewer (with timestamps in date range)
- **Passive**: review-requested, assignee, mentioned (no timestamp filtering)

Items are only included in final output if they have at least one active interaction within the date range.

### Parallel Processing

Uses `ThreadPoolExecutor` with 10 workers to fetch interaction details from GitHub API concurrently. Each item requires 2-3 API calls (comments, reviews, PR details), so parallelization significantly improves performance.

### Multiple Users/Orgs

When multiple users or organizations are specified:
- Results are deduplicated by URL
- Interactions are tagged with username: "reviewer (@user1)"
- Output groups by user first, then repository
- Each user's interactions are tracked separately on shared items

## Output Format

Single user: Groups by repository
Multiple users: Groups by user, then repository

Markdown tables include:
- Type (PR/Issue)
- State (OPEN/CLOSED/MERGED)
- Title (truncated to 60 chars)
- Interactions (comma-separated list)

Summary section shows PR/Issue count breakdown and interaction type frequency.

## Health Stats Mode

The script includes a `--health` mode that analyzes repository health metrics over time, tracking trends in issue/PR activity, response times, and release cadence.

### Health Mode Overview

Health mode collects and displays key repository health metrics:
- **Issue/PR Counts**: Open issues, open PRs, new issues/PRs in time period
- **Response Times**: Average time to first response on issues and PRs
- **Release Activity**: Days since last release
- **PR Cycle Time**: Average time from PR creation to merge

Data is stored in a local SQLite database (`~/.gh-contrib/health.db`) for historical trending and cached to minimize API calls.

### Health Mode CLI Arguments

```bash
# Enable health stats mode
--health                    Enable health stats mode (analyze repo health metrics)

# Target specification
--repos REPOS               Comma-separated repos (owner/repo). Defaults to all in --org
--weeks WEEKS               Number of weeks of history to analyze (default: 4)

# Metric filtering
--health-metrics METRICS    Comma-separated metrics to display (default: all)
                           Valid: open-issues, open-prs, new-issues, new-prs,
                                 days-since-release, avg-issue-response,
                                 avg-pr-response, avg-pr-cycle

# Bot filtering
--ignore-users USERS        Comma-separated usernames to treat as bots for response time

# Data management
--refresh                   Force refresh: fetch fresh data and update cache
--dry-run                   Preview API calls without executing (for rate limit planning)
```

### Health Mode Usage Examples

```bash
# Basic health stats for all repos in org (4 weeks default)
./gh-contrib --health --org crossplane

# Specific repositories only
./gh-contrib --health --org crossplane --repos crossplane/crossplane,crossplane/provider-aws

# Extended history analysis
./gh-contrib --health --org crossplane --weeks 8

# Focus on specific metrics
./gh-contrib --health --org crossplane --health-metrics open-issues,open-prs,avg-pr-response

# Force refresh cached data (bypass cache)
./gh-contrib --health --org crossplane --refresh

# Preview API calls without execution (debugging/planning)
./gh-contrib --health --org crossplane --dry-run

# Custom bot filtering for response times
./gh-contrib --health --org crossplane --ignore-users "ci-bot,release-automation"

# Multi-org analysis with specific repos
./gh-contrib --health --org "crossplane,kubernetes" --repos "crossplane/crossplane,kubernetes/kubernetes"
```

### Health Mode Output Format

#### Current Stats Table
Shows current week health metrics in a markdown table:
```
## Repository Health (Week of 01/06 - 01/12)

| Repository | Open Issues | Open PRs | New Issues | New PRs | Last Release | Issue Response | PR Response | PR Cycle |
|------------|-------------|----------|------------|---------|--------------|----------------|-------------|----------|
| crossplane/crossplane | 124 | 23 | 5 | 12 | 14d (v1.15.0) | 4.2h (n=50) | 2.1h (n=45) | 36.5h |
| crossplane/provider-aws | 89 | 15 | 3 | 8 | 7d (v0.47.0) | 6.8h (n=50) | 3.4h (n=38) | 48.2h |
| **Total/Avg** | **213** | **38** | **8** | **20** | - | **5.5h** | **2.8h** | **42.4h** |
```

#### Trend Charts
When `plotext` is available and multiple weeks are requested, displays ASCII trend charts showing metric evolution over time. One chart per metric, with lines for each repository.

#### Column Descriptions
- **Open Issues/PRs**: Current total count (excluding drafts for PRs)
- **New Issues/PRs**: Items created within the week boundary
- **Last Release**: Days since most recent non-draft, non-prerelease release
- **Issue/PR Response**: Average hours to first non-author, non-bot comment/review (sample size in parentheses)
- **PR Cycle**: Average hours from PR open to merge for PRs merged in the period

### Health Mode Data Storage

- **Database Location**: `~/.gh-contrib/health.db` (SQLite)
- **Caching Strategy**: Week-based caching (Monday-Sunday UTC boundaries)
- **Data Retention**: Indefinite (historical trending)
- **Cache Invalidation**: Use `--refresh` to force fresh data collection

### Health Mode Integration

Health mode can be combined with existing workflow patterns:

```bash
# Use with existing Makefile patterns
make health-crossplane

# Chain with normal activity analysis
./gh-contrib --health --org myorg --weeks 4
./gh-contrib --username myuser --org myorg --last-week
```

### Health Metrics Definitions

- **Response Time**: Time from item creation to first qualifying response (comment/review from non-author, non-bot user)
- **PR Cycle Time**: Time from PR creation to merge (only merged PRs, not closed-without-merge)
- **Bot Detection**: Users with `[bot]` suffix, known bot list, or custom `--ignore-users` list
- **Sample Sizes**: Response times calculated from most recent 50 open items (deterministic sampling)
- **Week Boundaries**: Monday 00:00:00 UTC to Sunday 23:59:59 UTC (inclusive)
