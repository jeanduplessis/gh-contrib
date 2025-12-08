# gh-contrib

Track GitHub contributions across users and organizations.

## Overview

`gh-contrib` fetches and analyzes GitHub activity, showing issues and PRs where specified users have actively participated (authored, reviewed, or commented).

## Requirements

- Python 3.9+
- [GitHub CLI](https://cli.github.com/) installed and authenticated

## Usage

```bash
# Basic usage
./gh-contrib --username <username> --org <org>

# Last complete week (Monday-Sunday)
./gh-contrib -u username -o myorg --last-week

# Multiple users and orgs
./gh-contrib -u user1,user2 -o org1,org2 --days 14

# Using Makefile shortcuts
make help
make control-planes-last-week
```

## Options

- `-u, --username` - GitHub username(s) (comma-separated)
- `-o, --org` - GitHub organization(s) (comma-separated)
- `-d, --days` - Number of days to look back (default: 7)
- `-e, --end-date` - End date for search window (YYYY-MM-DD)
- `--last-week` - Search last complete week
- `--show-filtered` - Show filtered items with passive interactions

## Output

Results are grouped by repository and displayed in markdown tables, with a summary showing per-user statistics:

- PRs authored, reviewed, commented
- Issues authored, commented

## How It Works

The tool uses `gh search` to find relevant issues/PRs, then fetches detailed interaction data via the GitHub API in parallel. Only items with active participation within the date range are included in the output.
