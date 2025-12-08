# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains `gh-contrib`, an executable Python script that fetches and analyzes GitHub activity for users within organizations. It uses the GitHub CLI (`gh`) for authentication and API access, displaying issues and PRs where specified users have actively participated.

## Requirements

- Python 3.9+ (uses modern type hints like `list[dict]`)
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
