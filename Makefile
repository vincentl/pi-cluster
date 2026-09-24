# Static checks for the head node scripts.

SCRIPTS := $(wildcard head/*.sh)

.PHONY: check
check:
	shellcheck $(SCRIPTS)
	for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done
	@echo "make check: $(words $(SCRIPTS)) scripts clean"
