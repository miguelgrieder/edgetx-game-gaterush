# GateRush — needs lua5.2 (override: make LUA=/path/to/lua52 LUAC=/path/to/luac52)
LUA ?= lua5.2
LUAC ?= luac5.2
PY ?= python3
SCENARIOS = $(filter-out _%,$(basename $(notdir $(wildcard inputs/*.lua))))

.PHONY: all build test frames sim dist clean lint soak calibrate

all: build test

build:
	$(LUA) tools/build.lua
	$(LUAC) -p dist/SCRIPTS/TOOLS/gaterush.lua

test: build
	$(LUA) tests/run_all.lua

soak:
	$(LUA) tools/soak.lua 100

calibrate:
	$(LUA) tools/calibrate.lua 20 300 0 0 2 1 4 2 8 4

frames: build
	@for s in $(SCENARIOS); do $(LUA) tools/run_frames.lua --script inputs/$$s.lua --out out/$$s || exit 1; done

# luacheck if installed; the built file must never write a global
lint: build
	-luacheck src tools tests
	@! $(LUAC) -l -p dist/SCRIPTS/TOOLS/gaterush.lua | grep 'SETTABUP.*_ENV' || (echo "global write in dist"; exit 1)

# Level 2: real firmware (Companion simulator DLLs, Windows x64), see tools/simhost/README.md
SIMU_DLLS ?= ../companion/bin
RADIO ?= tx12
SIMU = $(PY) tools/simhost/simu_host.py --dll-dir $(SIMU_DLLS) --radio $(RADIO)
sim: build
	$(SIMU) --sd dist --tool GateRush --inputs tools/simhost/inputs/play.txt --tail 2000 --out out/simu/play
	$(SIMU) --sd dist --tool GateRush --inputs tools/simhost/inputs/settings.txt --out out/simu/settings
	$(SIMU) --sd tools/simhost/gfxsd --tool GfxTest --frames 20 --out out/simu/gfx
	$(LUA) tools/simhost/compare.lua out/simu/gfx out/simu/play out/simu/settings

dist: build

clean:
	rm -rf out dist/SCRIPTS/TOOLS/gaterush.lua
