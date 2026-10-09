#!/usr/bin/env python3
"""Run a Lua tool inside the REAL EdgeTX firmware (Companion simulator DLL), headless.
Stdlib + ctypes only. See README.md."""
import argparse
import ctypes as C
import os
import re
import shutil
import sys
import time

# firmware EnumKeys (radio/src/keys.h)
KEY = dict(MENU=0, EXIT=1, ENTER=2, PAGEUP=3, PAGEDN=4, UP=5, DOWN=6, LEFT=7,
           RIGHT=8, PLUS=9, MINUS=10, MODEL=11, TELE=12, SYS=13)
# stick name -> firmware analog index (verified empirically, see README)
STICK_IDX = dict(rud=0, ele=1, thr=2, ail=3)


class Sim:
    def __init__(self, dll_dir, radio, sd):
        dll_dir = os.path.abspath(dll_dir)
        os.add_dll_directory(dll_dir)
        os.environ['PATH'] = dll_dir + os.pathsep + os.environ['PATH']
        self.qt = C.CDLL(os.path.join(dll_dir, 'Qt6Core.dll'))
        self.dll = C.CDLL(os.path.join(dll_dir, 'libedgetx-%s-simulator.dll' % radio))
        self._argc = C.c_int(1)
        self._argv = (C.c_char_p * 2)(b'simu', None)
        self._app = C.create_string_buffer(512)
        self._f(self.qt, '??0QCoreApplication@@QEAA@AEAHPEAPEADH@Z', None,
                [C.c_void_p, C.POINTER(C.c_int), C.c_void_p, C.c_int])(
            self._app, C.byref(self._argc), self._argv, 0x0a0000)
        self._fromUtf8 = self._f(self.qt, '?fromUtf8@QString@@SA?AV1@PEBD_J@Z', C.c_void_p,
                                 [C.c_void_p, C.c_char_p, C.c_ssize_t])
        fac = self._f(self.dll, 'registerSimu', C.c_void_p, None)()
        vt = C.cast(C.cast(fac, C.POINTER(C.c_void_p))[0], C.POINTER(C.c_void_p))
        self.sim = C.CFUNCTYPE(C.c_void_p, C.c_void_p)(vt[3])(fac)  # factory->create()
        S = '@OpenTxSimulator@@'
        M = lambda n, r=None, a=(): self._f(self.dll, n, r, [C.c_void_p] + list(a))
        self._init = M('?init' + S + 'UEAAXXZ')
        self._setSd = M('?setSdPath' + S + 'UEAAXAEBVQString@@0@Z', None, [C.c_void_p, C.c_void_p])
        self._start = M('?start' + S + 'UEAAXPEBD_N@Z', None, [C.c_char_p, C.c_bool])
        self._stop = M('?stop' + S + 'UEAAXXZ')
        self._getLcd = M('?getLcd' + S + 'UEAAPEAEXZ', C.c_void_p)
        self._setAnalog = M('?setAnalogValue' + S + 'UEAAXEF@Z', None, [C.c_uint8, C.c_int16])
        self._setKey = M('?setKey' + S + 'UEAAXE_N@Z', None, [C.c_uint8, C.c_bool])
        self._rot = M('?rotaryEncoderEvent' + S + 'UEAAXH@Z', None, [C.c_int])
        self._cap = M('?getCapability' + S + 'UEAA?BHW4Capability@SimulatorInterface@@@Z', C.c_int, [C.c_int])
        self._sd = self._qstr(os.path.abspath(sd))
        self._st = self._qstr(os.path.join(os.path.abspath(sd), 'SETTINGS'))

    @staticmethod
    def _f(lib, name, res, args):
        f = getattr(lib, name)
        f.restype = res
        f.argtypes = args
        return f

    def _qstr(self, s):
        b = s.encode()
        buf = C.create_string_buffer(32)
        self._fromUtf8(buf, b, len(b))
        return buf

    def start(self):
        self._init(self.sim)
        self._setSd(self.sim, self._sd, self._st)
        self._start(self.sim, None, False)

    def stop(self): self._stop(self.sim)
    def has_rotary(self): return bool(self._cap(self.sim, 1))
    def set_analog(self, i, v): self._setAnalog(self.sim, i, int(v))
    def set_key(self, k, down): self._setKey(self.sim, k, bool(down))
    def rotary(self, steps): self._rot(self.sim, steps)
    def lcd(self): return C.string_at(self._getLcd(self.sim), 1024)


def pbm(buf, path):
    """128x64 1bpp page-packed LCD buffer -> PBM P1 (1 = dark pixel)."""
    rows = [' '.join('1' if buf[x + (y // 8) * 128] >> (y % 8) & 1 else '0' for x in range(128))
            for y in range(64)]
    with open(path, 'w', newline='\n') as f:
        f.write('P1\n128 64\n' + '\n'.join(rows) + '\n')


def parse_inputs(path):
    """lines: t_ms ail ele thr rud [key]   (# comments)."""
    steps = []
    for ln in open(path, encoding='utf-8'):
        ln = ln.split('#')[0].strip()
        if not ln:
            continue
        p = ln.split()
        steps.append((int(p[0]), [int(x) for x in p[1:5]], p[5].lower() if len(p) > 5 else 'none'))
    return sorted(steps, key=lambda s: s[0])


def tool_names(sd):
    names = []
    d = os.path.join(sd, 'SCRIPTS', 'TOOLS')
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if f.endswith('.lua'):
            m = re.search(r'TNS\|(.*?)\|TNE', open(os.path.join(d, f), errors='ignore').read(400))
            names.append(m.group(1) if m else f[:-4])
    return names


class Runner:
    def __init__(self, sim, out, frame_ms):
        self.sim, self.out, self.n, self.frame_ms = sim, out, 0, frame_ms
        self.sticks = dict(ail=0, ele=0, thr=-1024, rud=0)
        self.pending = []
        self.record = False
        self.t0 = time.time()
        self.apply_sticks()

    def now(self): return (time.time() - self.t0) * 1000.0

    def apply_sticks(self):
        for n, v in self.sticks.items():
            self.sim.set_analog(STICK_IDX[n], v)

    def press(self, key, hold_ms=120):
        t = self.now()
        self.pending += [(t, key, True), (t + hold_ms, key, False)]

    def nav(self, which):
        if self.sim.has_rotary():
            self.sim.rotary(1 if which == 'next' else -1)
        else:
            self.press(KEY['PLUS'] if which == 'next' else KEY['MINUS'])

    def pump(self):
        t, keep = self.now(), []
        for (tt, k, d) in sorted(self.pending, key=lambda x: x[0]):
            if tt <= t:
                self.sim.set_key(k, d)
            else:
                keep.append((tt, k, d))
        self.pending = keep

    def maybe_dump(self):
        if self.record and self.now() >= self.t_rec0 + self.n * self.frame_ms:
            pbm(self.sim.lcd(), os.path.join(self.out, 'frame_%04d.pbm' % self.n))
            self.n += 1

    def wait(self, ms):
        end = self.now() + ms
        while self.now() < end:
            self.pump()
            self.maybe_dump()
            time.sleep(0.003)

    def start_record(self):
        self.record, self.t_rec0 = True, self.now()

    def key_event(self, k):
        if k == 'none':
            return
        if k in ('next', 'prev'):
            self.nav(k)
        elif k in ('rot_next', 'rot_prev'):  # raw rotary-encoder step (radios with a roller)
            self.sim.rotary(1 if k == 'rot_next' else -1)
        elif k.endswith('_long') and k[:-5].upper() in KEY:
            self.press(KEY[k[:-5].upper()], 700)
        elif k.upper() in KEY:
            self.press(KEY[k.upper()])
        else:
            raise SystemExit('unknown key ' + k)


def run_keys(r, spec, gap=350):
    for tok in [t.strip() for t in spec.split(',') if t.strip()]:
        r.key_event(tok.lower())
        r.wait(gap)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--dll-dir', required=True, help='folder with Qt6Core.dll, SDL2.dll, libedgetx-<radio>-simulator.dll')
    ap.add_argument('--radio', default='tx12')
    ap.add_argument('--sd', required=True, help='SD root (copied to <out>/_sd, never modified)')
    ap.add_argument('--tool', required=True, help='tool display name from "-- TNS|name|TNE"')
    ap.add_argument('--inputs', help='timed input file (see README)')
    ap.add_argument('--frames', type=int, default=100, help='frames to record when no --inputs')
    ap.add_argument('--tail', type=int, default=500, help='ms to keep recording after the last input step')
    ap.add_argument('--out', required=True)
    ap.add_argument('--frame-ms', type=int, default=50)
    ap.add_argument('--boot-ms', type=int, default=3500)
    ap.add_argument('--nav', help='override launch navigation, e.g. "sys,next,next,enter"')
    ap.add_argument('--no-launch', action='store_true')
    ap.add_argument('--stop-keys', default='', help='keys to press after the run (e.g. exit)')
    a = ap.parse_args()

    out = os.path.abspath(a.out)
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    sd = os.path.join(out, '_sd')
    shutil.copytree(a.sd, sd)
    for d in ('RADIO', 'MODELS', 'SETTINGS', 'SCRIPTS/TOOLS', 'LOGS'):
        os.makedirs(os.path.join(sd, d), exist_ok=True)
    names = tool_names(sd)
    if a.tool not in names:
        raise SystemExit('tool %r not in SCRIPTS/TOOLS (found %s)' % (a.tool, names))

    sys.stdout.flush()
    sys.stderr.flush()
    saved = os.dup(1)
    tr = os.open(os.path.join(out, 'firmware_trace.txt'), os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    os.dup2(tr, 1)
    os.dup2(tr, 2)
    real = os.fdopen(saved, 'w')

    sim = Sim(a.dll_dir, a.radio, sd)
    r = Runner(sim, out, a.frame_ms)
    sim.start()
    r.wait(a.boot_ms)
    run_keys(r, 'exit,exit', 300)  # dismiss throttle/switch/storage warnings
    if not a.no_launch:
        if a.nav:
            run_keys(r, a.nav)
        else:
            r.key_event('sys')
            r.wait(800)
            run_keys(r, ','.join(['next'] * names.index(a.tool)), 250)
            r.key_event('enter')
            r.wait(900)
    r.start_record()
    steps = parse_inputs(a.inputs) if a.inputs else []
    end = (steps[-1][0] + a.tail) if steps else a.frames * a.frame_ms
    t_start, si = r.now(), 0
    while r.now() - t_start < end:
        el = r.now() - t_start
        while si < len(steps) and steps[si][0] <= el:
            _, v, k = steps[si]
            for n, val in zip(('ail', 'ele', 'thr', 'rud'), v):
                r.sticks[n] = val
            r.apply_sticks()
            r.key_event(k)
            si += 1
        r.pump()
        r.maybe_dump()
        time.sleep(0.002)
    if a.stop_keys:
        run_keys(r, a.stop_keys)
    for k in range(14):
        sim.set_key(k, False)
    sim.stop()
    with open(os.path.join(out, 'log.txt'), 'w') as f:
        f.write('radio=%s tool=%s frames=%d frame_ms=%d inputs=%s\n' % (a.radio, a.tool, r.n, a.frame_ms, a.inputs))
        errs = [l.strip() for l in open(os.path.join(out, 'firmware_trace.txt'), errors='replace') if '-E-' in l or 'rror' in l]
        f.write('lua/firmware errors in trace: %d\n' % len(errs))
        for l in errs[:20]:
            f.write('  ' + l + '\n')
        f.write('tools in sd: %s\nfirmware/Lua trace: firmware_trace.txt (Lua errors show up there)\n' % names)
    print('frames written:', r.n, '->', out, file=real)
    real.flush()
    os._exit(0)  # firmware threads do not join cleanly


if __name__ == '__main__':
    main()
