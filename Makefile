.PHONY: help control-planes-last-week control-planes-last-week-debug control-planes-trends setup test test-verbose

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
	@echo "  make control-planes-trends           - Show 4-week trend charts for Crossplane team"

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
	$(PYTHON) ./gh-contrib --username jeanduplessis,phisco,jbw976,haarchri,adamwg,negz,ezgidemirel,lsviben --org crossplane,crossplane-contrib --trend --weeks 4
