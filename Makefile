PLATFORMS= \
	freebsd/amd64 \
	linux/386 \
	linux/amd64 \
	windows/386 \
	windows/amd64 \
	darwin/amd64 \
	$(NULL)

	# freebsd-386 \
	# freebsd-arm \
	# linux-arm \
	# openbsd-386 \
	# openbsd-amd64 \
	# darwin-386

NAME=jira

OS=$(shell uname -s)
ifeq ($(filter CYGWIN%,$(OS)),$(OS))
	export CWD=$(shell cygpath -wa .)
	export SEP=\\
	export CYGWIN=winsymlinks:native
	BIN ?= $(GOBIN)$(SEP)$(NAME).exe
else
	export CWD=$(shell pwd)
	export SEP=/
	BIN ?= $(GOBIN)$(SEP)$(NAME)
endif

export GOPATH=$(CWD)

DIST=$(CWD)$(SEP)dist

GOBIN ?= $(CWD)

CURVER ?= $(patsubst v%,%,$(shell [ -d .git ] && git describe --abbrev=0 --tags || grep ^\#\# CHANGELOG.md | awk '{print $$2; exit}'))
LDFLAGS:=-X jira.VERSION=$(CURVER) -w

# use make DEBUG=1 and you can get a debuggable golang binary
# see https://github.com/mailgun/godebug
ifneq ($(DEBUG),)
	GOBUILD=go get -v github.com/mailgun/godebug && ./bin/godebug build
else
	GOBUILD=go build -v -ldflags "$(LDFLAGS) -s"
endif

build: src/gopkg.in/Netflix-Skunkworks/go-jira.v0
	$(GOBUILD) -o '$(BIN)' main/main.go

debug:
	$(MAKE) DEBUG=1

src/%:
	mkdir -p $(@D)
	test -L $@ || ln -sf '../../..' $@
	go get -v $* $*/main

vet:
	@go vet .
	@go vet ./data
	@go vet ./main

lint:
	@go get github.com/golang/lint/golint
	@./bin/golint .
	@./bin/golint ./data
	@./bin/golint ./main

cross-setup:
	for p in $(PLATFORMS); do \
        echo Building for $$p"; \
		cd $(GOROOT)/src && sudo GOROOT_BOOTSTRAP=$(GOROOT) GOOS=$${p/-*/} GOARCH=$${p/*-/} bash ./make.bash --no-clean; \
   done

all: 
	git push --tags
	rm -rf src
	${MAKE} src/gopkg.in/Netflix-Skunkworks/go-jira.v0
	docker pull karalabe/xgo-latest
	rm -rf dist
	mkdir -p dist
	docker run --rm -e EXT_GOPATH=/gopath -v $$(pwd):/gopath -e TARGETS="$(PLATFORMS)" -v $$(pwd)/dist:/build karalabe/xgo-latest gopkg.in/Netflix-Skunkworks/go-jira.v0/main
	cd $(DIST) && for x in main-*; do mv $$x jira-$$(echo $$x | cut -c 6-); done

# all:
# 	rm -rf $(DIST); \
# 	mkdir -p $(DIST); \
# 	for p in $(PLATFORMS); do \
#         echo "Building for $$p"; \
#         ${MAKE} build GOOS=$${p/-*/} GOARCH=$${p/*-/} BIN=$(DIST)/$(NAME)-$$p; \
#     done
# 	for x in $(DIST)/jira-windows-*; do mv $$x $$x.exe; done

fmt:
	gofmt -s -w main/*.go *.go

install:
	${MAKE} GOBIN=$$HOME/bin build

NEWVER ?= $(shell echo $(CURVER) | awk -F. '{print $$1"."$$2"."$$3+1}')
TODAY  := $(shell date +%Y-%m-%d)

changes:
	@git log --pretty=format:"* %s [%cn] [%h]" --no-merges ^v$(CURVER) HEAD main/*.go *.go | grep -vE 'gofmt|go fmt'

update-changelog:
	@echo "# Changelog" > CHANGELOG.md.new; \
	echo >> CHANGELOG.md.new; \
	echo "## $(NEWVER) - $(TODAY)" >> CHANGELOG.md.new; \
	echo >> CHANGELOG.md.new; \
	$(MAKE) --no-print-directory --silent changes | \
	perl -pe 's{\[([a-f0-9]+)\]}{[[$$1](https://github.com/Netflix-Skunkworks/go-jira/commit/$$1)]}g' | \
	perl -pe 's{\#(\d+)}{[#$$1](https://github.com/Netflix-Skunkworks/go-jira/issues/$$1)}g' >> CHANGELOG.md.new; \
	tail -n +2 CHANGELOG.md >> CHANGELOG.md.new; \
	mv CHANGELOG.md.new CHANGELOG.md; \
	git commit -m "Updated Changelog" CHANGELOG.md; \
	git tag v$(NEWVER)

version:
	@echo $(CURVER)

clean:
	rm -rf pkg dist bin src ./$(NAME)

export GNUPGHOME=$(CWD)/t/.gnupg
export PASSWORD_STORE_DIR=$(CWD)/t/.password-store
export JIRACLOUD=1

prove:
	chmod -R g-rwx,o-rwx $(GNUPGHOME)
	OSHT_VERBOSE=1 prove -v 
