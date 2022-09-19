# Makefile for scriv
#
# To release:
#   - increment the version in src/scriv/__init__.py
#   - scriv collect
#   - commit changes
#   - make check_release
#   - make release

.PHONY: clean coverage docs help \
	quality requirements test test-all upgrade validate

.DEFAULT_GOAL := help

# For opening files in a browser. Use like: $(BROWSER)relative/path/to/file.html
BROWSER := python -m webbrowser file://$(CURDIR)/

help: ## display this help message
	@echo "Please use \`make <target>' where <target> is one of"
	@awk -F ':.*?## ' '/^[a-zA-Z]/ && NF==2 {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

clean: ## remove generated byte code, coverage reports, and build artifacts
	find . -name '__pycache__' -exec rm -rf {} +
	find . -name '*.pyc' -exec rm -f {} +
	find . -name '*.pyo' -exec rm -f {} +
	find . -name '*~' -exec rm -f {} +
	coverage erase
	rm -fr build/
	rm -fr dist/
	rm -fr *.egg-info
	rm -fr htmlcov/
	rm -fr .*_cache/
	cd docs; make clean

coverage: clean ## generate and view HTML coverage report
	tox -e py37,py311,coverage
	$(BROWSER)htmlcov/index.html

docs: botedits ## generate Sphinx HTML documentation, including API docs
	tox -e docs
	$(BROWSER)docs/_build/html/index.html

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: ## update the requirements/*.txt files with the latest packages satisfying requirements/*.in
	pip install -qr requirements/pip-tools.txt
	# Make sure to compile files after any other files they include!
	pip-compile --upgrade -o requirements/pip-tools.txt requirements/pip-tools.in
	pip-compile --upgrade -o requirements/base.txt requirements/base.in
	pip-compile --upgrade -o requirements/test.txt requirements/test.in
	pip-compile --upgrade -o requirements/doc.txt requirements/doc.in
	pip-compile --upgrade -o requirements/quality.txt requirements/quality.in
	pip-compile --upgrade -o requirements/tox.txt requirements/tox.in
	pip-compile --upgrade -o requirements/dev.txt requirements/dev.in
	# Splice requirements/base.in into setup.cfg
	sed -n -e '1,/begin_install_requires/p' < setup.cfg > setup.tmp
	sed -n -e '/^[a-zA-Z]/s/^/    /p' < requirements/base.in >> setup.tmp
	sed -n -e '/end_install_requires/,$$p' < setup.cfg >> setup.tmp
	mv setup.tmp setup.cfg

botedits: ## make source edits by tools
	python -m black --line-length=80 src/scriv tests docs setup.py
	python -m cogapp -crP docs/*.rst

quality: ## check coding style with pycodestyle and pylint
	tox -e quality

requirements: ## install development environment requirements
	pip install -qr requirements/pip-tools.txt
	pip-sync requirements/dev.txt

test: ## run tests in the current virtualenv
	tox -e py38

test-all: ## run tests on every supported Python combination
	tox

validate: clean botedits quality test ## run tests and quality checks

.PHONY: dist pypi testpypi tag gh_release

dist: ## Build the distributions
	python -m build --sdist --wheel

pypi: ## Upload the built distributions to PyPI.
	python -m twine upload --verbose dist/*

testpypi: ## Upload the distrubutions to PyPI's testing server.
	python -m twine upload --verbose --repository testpypi dist/*

tag: ## Make a git tag with the version number
	git tag -a -m "Version $$(python setup.py --version)" $$(python setup.py --version)
	git push --all

gh_release: ## Make a GitHub release
	python -m scriv github-release --all

.PHONY: release check_release _check_manifest _check_version _check_scriv

release: clean check_release dist pypi tag gh_release ## do all the steps for a release

check_release: _check_manifest _check_tree _check_version _check_scriv ## check that we are ready for a release
	@echo "Release checks passed"

_check_manifest:
	python -m check_manifest

_check_tree:
	@if [[ -n $$(git status --porcelain) ]]; then \
		echo 'There are modified files! Did you forget to check them in?'; \
		exit 1; \
	fi

_check_version:
	@if [[ $$(git tags | grep -q -w $$(python setup.py --version) && echo "x") == "x" ]]; then \
		echo 'A git tag for this version exists! Did you forget to bump the version in src/scriv/__init__.py?'; \
		exit 1; \
	fi

_check_scriv:
	@if (( $$(ls -1 changelog.d | wc -l) != 1 )); then \
		echo 'There are scriv fragments! Did you forget `scriv collect`?'; \
		exit 1; \
	fi
