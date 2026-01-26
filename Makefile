.PHONY: help control-planes-last-week control-planes-last-week-debug control-planes-trends setup test test-verbose health-crossplane health-crossplane-dry-run health-crossplane-trends health-kubernetes health-example

# Python to use - prefer venv if it exists
PYTHON := $(shell [ -x .venv/bin/python3 ] && echo .venv/bin/python3 || echo python3)

# Default target - show available commands
help:
	@echo "Available commands:"
	@echo "  make setup                           - Set up virtual environment with dependencies"
	@echo "  make test                            - Run unit tests"
	@echo "  make test-verbose                    - Run unit tests with verbose output"
	@echo "  make control-planes-last-week        - Show Crossplane team summary for last week"
	@echo "  make control-planes-last-week-debug  - Show detailed activity for last week"
	@echo "  make control-planes-trends           - Show 5-week trend charts for Crossplane team"
	@echo ""
	@echo "Health mode targets:"
	@echo "  make health-crossplane               - Basic health stats for Crossplane org (4 weeks)"
	@echo "  make health-crossplane-dry-run       - Preview health stats API calls for Crossplane (dry run)"
	@echo "  make health-crossplane-trends        - Extended health trends for Crossplane (8 weeks)"
	@echo "  make health-kubernetes               - Health stats for Kubernetes org core repos"
	@echo "  make health-example                  - Example health stats with custom metrics"

# Run tests
test:
	$(PYTHON) -m unittest test_gh_contrib -q

test-verbose:
	$(PYTHON) -m unittest test_gh_contrib -v

# Set up virtual environment
setup:
	python3 -m venv .venv
	.venv/bin/pip install plotext

# Show Crossplane control-planes team activity for the last complete week
control-planes-last-week:
	$(PYTHON) ./gh-contrib --username jeanduplessis,phisco,jbw976,haarchri,adamwg,negz,ezgidemirel,lsviben --org crossplane,crossplane-contrib --last-week

control-planes-last-week-debug:
	$(PYTHON) ./gh-contrib --username jeanduplessis,phisco,jbw976,haarchri,adamwg,negz,ezgidemirel,lsviben --org crossplane,crossplane-contrib --last-week --debug

control-planes-trends:
	$(PYTHON) ./gh-contrib --username jeanduplessis,phisco,jbw976,haarchri,adamwg,negz,ezgidemirel,lsviben --org crossplane,crossplane-contrib --trend --weeks 5

# Health mode targets for repository health analysis
health-crossplane:
	$(PYTHON) ./gh-contrib --health --org crossplane --weeks 4

health-crossplane-dry-run:
	$(PYTHON) ./gh-contrib --health --org crossplane --weeks 4 --dry-run

health-crossplane-trends:
	$(PYTHON) ./gh-contrib --health --org crossplane --weeks 8

health-example:
	$(PYTHON) ./gh-contrib --health --org crossplane --repos crossplane/crossplane,crossplane/crossplane-runtime --health-metrics open-issues,open-prs,avg-pr-response,avg-pr-cycle --weeks 6 --ignore-users "dependabot,renovate,coderabbitai"
