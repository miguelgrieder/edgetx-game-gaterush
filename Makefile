# GateRush — needs lua5.2 (override: make LUA=/path/to/lua52 LUAC=/path/to/luac52)
LUA ?= lua5.2
LUAC ?= luac5.2
PY ?= python3
SCENARIOS = $(basename $(notdir $(wildcard inputs/*.lua)))

.PHONY: all build test frames sim dist clean lint

all: build test

build:
	$(LUA) tools/build.lua
	$(LUAC) -p dist/SCRIPTS/TOOLS/gaterush.lua

test: build
	$(LUA) tests/run_all.lua

frames: build
	@for s in $(SCENARIOS); do $(LUA) tools/run_frames.lua --frames 600 --script inputs/$$s.lua --out out/$$s || exit 1; done

lint:
	luacheck src tools tests

sim: build
	$(MAKE) -C tools/simhost run

dist: build

clean:
	rm -rf out dist/SCRIPTS/TOOLS/gaterush.lua
