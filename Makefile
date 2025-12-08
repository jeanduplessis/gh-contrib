.PHONY: help control-planes-last-week

# Default target - show available commands
help:
	@echo "Available commands:"
	@echo "  make control-planes-last-week  - Show Crossplane team activity for last week"

# Show Crossplane control-planes team activity for the last complete week
control-planes-last-week:
	./gh-contrib --username jeanduplessis,phisco,jbw976,haarchri,adamwg,negz,ezgidemirel,lsviben --org crossplane,crossplane-contrib --last-week
