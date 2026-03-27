SWIFTLINT ?= swiftlint
SWIFTFORMAT ?= swiftformat

.PHONY: lint lint-fix analyze format format-check

lint:
	$(SWIFTLINT) lint --strict

lint-fix:
	$(SWIFTLINT) lint --fix --strict

analyze:
	$(SWIFTLINT) analyze --strict --compiler-log-path build.log

format:
	$(SWIFTFORMAT) .

format-check:
	$(SWIFTFORMAT) . --lint
