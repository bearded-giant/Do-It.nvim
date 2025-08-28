.PHONY: help test check-docs update-help docker-interactive

help:
	@echo "Available targets:"
	@echo "  test              Run the test suite in Docker"
	@echo "  check-docs        Check documentation for duplicate tags and invalid references"
	@echo "  update-help       Update HELP.txt from central help module"
	@echo "  docker-interactive Run interactive Docker environment"
	@echo "  help              Show this help message"

test:
	docker/run-tests.sh

update-help:
	@echo "Updating docker/HELP.txt from lua/doit/help.lua..."
	@cd docker && lua generate-help.lua
	@echo "HELP.txt updated successfully"

docker-interactive:
	docker/run-interactive.sh

check-docs:
	@echo "Checking for duplicate help tags..."
	@duplicates=$$(grep -o '\*[^*]*\*' doc/*.txt | sort | uniq -c | awk '$$1 > 1 {print $$0}'); \
	if [ -n "$$duplicates" ]; then \
		echo "Error: Duplicate help tags found:"; \
		echo "$$duplicates"; \
		exit 1; \
	else \
		echo "No duplicate help tags found."; \
	fi
	
	@echo ""
	@echo "Checking for invalid tag references..."
	@invalid_count=0; \
	for tag in $$(grep -o '\*[^*]*\*' doc/*.txt | sort | uniq); do \
		ref=$${tag//\*/|}; \
		if ! grep -q "$$ref" doc/*.txt && [ "$$tag" != "*doit*" ] && [ "$$tag" != "*doit.txt*" ] && [ "$$tag" != "*doit_framework.txt*" ] && [ "$$tag" != "*doit_linking.txt*" ]; then \
			echo "Warning: Tag $$tag has no corresponding reference ($$ref)"; \
			invalid_count=$$((invalid_count + 1)); \
		fi; \
	done; \
	if [ $$invalid_count -gt 0 ]; then \
		echo ""; \
		echo "Found $$invalid_count tags without references."; \
		echo "Consider adding references to improve navigation."; \
	else \
		echo "All tags have proper references."; \
	fi