// Palm OS emulation, part 1: the world state, C helpers used by the
// transpiled code, strings, memory, preferences and databases.
package game

import "base:runtime"
import "core:mem"

SCREEN_W :: 160
SCREEN_H :: 160
FB_W :: SCREEN_W * 2 // the framebuffer is double density
FB_H :: SCREEN_H * 2

MAX_FORMS :: 6
MAX_OBJS :: 72
LABEL_CAP :: 80
MAX_EVENTS :: 32

// Everything the replay engine snapshots and restores (see palm_run.odin).
World :: struct {
	g:        Globals,
	fb:       [FB_W * FB_H]u8,
	clip:     Rect,
	font:     i32,
	forms:    [MAX_FORMS]FormType,
	active:   i32, // index into forms, -1 = none
	queue:    [MAX_EVENTS]EventType,
	q_head:   i32,
	q_len:    i32,
	rand:     u32,
	ticks:    u32,
	db:       Db_Store,
}

world: World
g := &world.g

Rect :: struct {
	x, y, w, h: i32,
}

// ---------------------------------------------------------------- C helpers

b2i :: #force_inline proc "contextless" (b: bool) -> i32 {return 1 if b else 0}

assign :: #force_inline proc "contextless" (p: ^$T, v: T) -> T {p^ = v; return v}
post_inc :: #force_inline proc "contextless" (p: ^$T) -> T {o := p^; p^ += 1; return o}
post_dec :: #force_inline proc "contextless" (p: ^$T) -> T {o := p^; p^ -= 1; return o}
pre_inc :: #force_inline proc "contextless" (p: ^$T) -> T {p^ += 1; return p^}
pre_dec :: #force_inline proc "contextless" (p: ^$T) -> T {p^ -= 1; return p^}
compound_add :: #force_inline proc "contextless" (p: ^$T, v: T) -> T {p^ += v; return p^}
compound_sub :: #force_inline proc "contextless" (p: ^$T, v: T) -> T {p^ -= v; return p^}
compound_mul :: #force_inline proc "contextless" (p: ^$T, v: T) -> T {p^ *= v; return p^}
compound_div :: #force_inline proc "contextless" (p: ^$T, v: T) -> T {p^ /= v; return p^}
compound_mod :: #force_inline proc "contextless" (p: ^$T, v: T) -> T {p^ %= v; return p^}
compound_and :: #force_inline proc "contextless" (p: ^$T, v: T) -> T {p^ &= v; return p^}
compound_or :: #force_inline proc "contextless" (p: ^$T, v: T) -> T {p^ |= v; return p^}

cidx :: #force_inline proc "contextless" (s: cstring) -> [^]u8 {return transmute([^]u8)s}
cadd :: #force_inline proc "contextless" (s: cstring, n: i32) -> cstring {return cstring(&cidx(s)[n])}

cstr_init :: proc "contextless" (dst: []u8, src: cstring) {
	s := cidx(src)
	i := 0
	for i < len(dst) - 1 && s[i] != 0 {
		dst[i] = s[i]
		i += 1
	}
	dst[i] = 0
}

// Odin string view of a C string (no copy).
cs :: proc "contextless" (s: cstring) -> string {
	if s == nil {return ""}
	return string(s)
}

buf_str :: proc "contextless" (b: []u8) -> string {
	for c, i in b {
		if c == 0 {return string(b[:i])}
	}
	return string(b)
}

// ---------------------------------------------------------------- strings

StrCopy :: proc "contextless" (dst: cstring, src: cstring) -> cstring {
	d := cidx(dst)
	s := cidx(src)
	i := 0
	if src != nil {
		for s[i] != 0 {
			d[i] = s[i]
			i += 1
		}
	}
	d[i] = 0
	return dst
}

StrNCopy :: proc "contextless" (dst: cstring, src: cstring, n: i16) -> cstring {
	d := cidx(dst)
	s := cidx(src)
	i := 0
	for i < int(n) && s[i] != 0 {
		d[i] = s[i]
		i += 1
	}
	for i < int(n) {
		d[i] = 0
		i += 1
	}
	return dst
}

StrLen :: proc "contextless" (s: cstring) -> i16 {
	if s == nil {return 0}
	p := cidx(s)
	n: i16 = 0
	for p[n] != 0 {n += 1}
	return n
}

StrCat :: proc "contextless" (dst: cstring, src: cstring) -> cstring {
	n := StrLen(dst)
	StrCopy(cstring(&cidx(dst)[n]), src)
	return dst
}

StrIToA :: proc "contextless" (s: cstring, i: i32) -> cstring {
	d := cidx(s)
	tmp: [12]u8
	n := 0
	v := i64(i)
	neg := v < 0
	if neg {v = -v}
	if v == 0 {
		tmp[0] = '0'
		n = 1
	}
	for v > 0 {
		tmp[n] = u8('0' + v % 10)
		v /= 10
		n += 1
	}
	k := 0
	if neg {
		d[0] = '-'
		k = 1
	}
	for j := n - 1; j >= 0; j -= 1 {
		d[k] = tmp[j]
		k += 1
	}
	d[k] = 0
	return s
}

StrAToI :: proc "contextless" (s: cstring) -> i32 {
	p := cidx(s)
	i := 0
	for p[i] == ' ' {i += 1}
	neg := false
	if p[i] == '-' {
		neg = true
		i += 1
	} else if p[i] == '+' {
		i += 1
	}
	v: i32 = 0
	for p[i] >= '0' && p[i] <= '9' {
		v = v * 10 + i32(p[i] - '0')
		i += 1
	}
	return -v if neg else v
}

StrCompare :: proc "contextless" (a: cstring, b: cstring) -> i16 {
	pa, pb := cidx(a), cidx(b)
	i := 0
	for {
		ca, cb := pa[i], pb[i]
		if ca != cb {return i16(ca) - i16(cb)}
		if ca == 0 {return 0}
		i += 1
	}
}

StrNCompare :: proc "contextless" (a: cstring, b: cstring, n: i32) -> i16 {
	pa, pb := cidx(a), cidx(b)
	for i in 0 ..< int(n) {
		ca, cb := pa[i], pb[i]
		if ca != cb {return i16(ca) - i16(cb)}
		if ca == 0 {return 0}
	}
	return 0
}

lower :: #force_inline proc "contextless" (c: u8) -> u8 {return c + 32 if c >= 'A' && c <= 'Z' else c}

StrCaselessCompare :: proc "contextless" (a: cstring, b: cstring) -> i16 {
	pa, pb := cidx(a), cidx(b)
	i := 0
	for {
		ca, cb := lower(pa[i]), lower(pb[i])
		if ca != cb {return i16(ca) - i16(cb)}
		if ca == 0 {return 0}
		i += 1
	}
}

StrToLower :: proc "contextless" (dst: cstring, src: cstring) -> cstring {
	d, s := cidx(dst), cidx(src)
	i := 0
	for s[i] != 0 {
		d[i] = lower(s[i])
		i += 1
	}
	d[i] = 0
	return dst
}

// Only "%d" and "%ld" occur in Space Trader.
StrPrintF :: proc(s: cstring, format: cstring, args: ..any) -> i16 {
	d := cidx(s)
	f := cidx(format)
	k := 0
	ai := 0
	i := 0
	for f[i] != 0 {
		if f[i] == '%' {
			i += 1
			for f[i] == 'l' {i += 1}
			if f[i] == 'd' && ai < len(args) {
				v: i32 = 0
				switch x in args[ai] {
				case i32: v = x
				case i16: v = i32(x)
				case u16: v = i32(x)
				case u8: v = i32(x)
				case int: v = i32(x)
				}
				ai += 1
				tmp: [12]u8
				StrIToA(cstring(&tmp[0]), v)
				for j := 0; tmp[j] != 0; j += 1 {
					d[k] = tmp[j]
					k += 1
				}
			} else {
				d[k] = f[i]
				k += 1
			}
			i += 1
			continue
		}
		d[k] = f[i]
		k += 1
		i += 1
	}
	d[k] = 0
	return i16(k)
}

string_by_id :: proc(id: i32) -> string {
	lo, hi := 0, len(STRING_DEFS) - 1
	for lo <= hi {
		mid := (lo + hi) / 2
		v := i32(STRING_DEFS[mid].id)
		if v == id {return STRING_DEFS[mid].text}
		if v < id {lo = mid + 1} else {hi = mid - 1}
	}
	return ""
}

copy_to_c :: proc "contextless" (dst: cstring, src: string, max_len: int) {
	d := cidx(dst)
	n := min(len(src), max_len - 1)
	for i in 0 ..< n {d[i] = src[i]}
	d[n] = 0
}

SysStringByIndex :: proc(resID: u16, index: u16, strP: cstring, maxLen: u16) -> cstring {
	for def in STRING_LIST_DEFS {
		if def.id == resID {
			if int(index) < int(def.count) {
				copy_to_c(strP, RSRC_POOL[int(def.first) + int(index)], int(maxLen))
				return strP
			}
		}
	}
	copy_to_c(strP, "", int(maxLen))
	return strP
}

SysCopyStringResource :: proc(str: cstring, theID: i16) {
	s := string_by_id(i32(theID))
	copy_to_c(str, s, len(s) + 1)
}

// ---------------------------------------------------------------- memory

MemHandle :: rawptr
DmOpenRef :: rawptr
FormEventHandlerType :: proc(eventP: ^EventType) -> bool

MemHandleNew :: proc(size: u32) -> MemHandle {
	b, _ := mem.alloc(int(size) + 1)
	return b
}
MemHandleLock :: proc "contextless" (h: MemHandle) -> rawptr {return h}
MemHandleUnlock :: proc "contextless" (h: MemHandle) -> u16 {return 0}
MemPtrUnlock :: proc "contextless" (p: rawptr) -> u16 {return 0}
MemHandleFree :: proc(h: MemHandle) -> u16 {
	free(h)
	return 0
}
MemMove :: proc "contextless" (dst: rawptr, src: rawptr, n: i32) -> u16 {
	mem.copy(dst, src, int(n))
	return 0
}
MemSet :: proc "contextless" (dst: rawptr, n: i32, v: u8) -> u16 {
	mem.set(dst, v, int(n))
	return 0
}

// ---------------------------------------------------------------- databases
// Palm databases with one record each (save game, switch game, high scores)
// and the app preferences (the autosave). Kept in World so a replay restores
// them; the platform persists `world.db` after each finished transaction.

DB_SLOTS :: 4
DB_RECORD_CAP :: 16384

Db :: struct {
	used:    bool,
	name:    [32]u8,
	size:    i32,
	has_rec: bool,
	data:    [DB_RECORD_CAP]u8,
}

Db_Store :: struct {
	dbs:     [DB_SLOTS]Db, // slot 0 is the preferences
	dirty:   bool,
}

PREFS_NAME :: "__prefs__"

db_find :: proc(name: string) -> i32 {
	for i in 0 ..< DB_SLOTS {
		d := &world.db.dbs[i]
		if d.used && buf_str(d.name[:]) == name {return i32(i)}
	}
	return -1
}

db_create :: proc(name: string) -> i32 {
	for i in 1 ..< DB_SLOTS {
		d := &world.db.dbs[i]
		if !d.used {
			d^ = {}
			d.used = true
			copy(d.name[:31], name)
			world.db.dirty = true
			return i32(i)
		}
	}
	return -1
}

// LocalID = slot + 1, DmOpenRef = pointer to the Db
DmFindDatabase :: proc(cardNo: u16, nameP: cstring) -> u32 {
	i := db_find(cs(nameP))
	return u32(i + 1) if i >= 0 else 0
}
DmCreateDatabase :: proc(cardNo: u16, nameP: cstring, creator: u32, type: u32, resDB: bool) -> u16 {
	if db_find(cs(nameP)) >= 0 {return 0}
	return 0 if db_create(cs(nameP)) >= 0 else 1
}
DmOpenDatabase :: proc(cardNo: u16, dbID: u32, mode: u16) -> DmOpenRef {
	if dbID == 0 || dbID > DB_SLOTS {return nil}
	return &world.db.dbs[dbID - 1]
}
DmCloseDatabase :: proc(dbP: DmOpenRef) -> u16 {return 0}
DmGetRecord :: proc(dbP: DmOpenRef, index: u16) -> MemHandle {
	d := cast(^Db)dbP
	if d == nil || !d.has_rec || index != 0 {return nil}
	return &d.data[0]
}
DmNewRecord :: proc(dbP: DmOpenRef, atP: [^]u16, size: u32) -> MemHandle {
	d := cast(^Db)dbP
	if d == nil || size > DB_RECORD_CAP {return nil}
	d.has_rec = true
	d.size = i32(size)
	if atP != nil {atP[0] = 0}
	world.db.dirty = true
	return &d.data[0]
}
DmReleaseRecord :: proc(dbP: DmOpenRef, index: u16, dirty: bool) -> u16 {
	if dirty {world.db.dirty = true}
	return 0
}
DmWrite :: proc(recordP: rawptr, offset: u32, srcP: rawptr, bytes: u32) -> u16 {
	mem.copy(rawptr(uintptr(recordP) + uintptr(offset)), srcP, int(bytes))
	world.db.dirty = true
	return 0
}
DmDatabaseInfo :: proc(cardNo: u16, dbID: u32, nameP: cstring, attributesP: [^]u16, versionP: [^]u16, crDateP, modDateP, bckUpDateP, modNumP: [^]u32, appInfoIDP, sortInfoIDP: [^]u32, typeP, creatorP: [^]u32) -> u16 {
	if attributesP != nil {attributesP[0] = 0}
	return 0
}
DmSetDatabaseInfo :: proc(cardNo: u16, dbID: u32, nameP: cstring, attributesP: [^]u16, versionP: [^]u16, crDateP, modDateP, bckUpDateP, modNumP: [^]u32, appInfoIDP, sortInfoIDP: [^]u32, typeP, creatorP: [^]u32) -> u16 {return 0}
DmOpenDatabaseInfo :: proc(dbP: DmOpenRef, dbIDP: [^]u32, openCountP: [^]u16, modeP: [^]u16, cardNoP: [^]u16, resDBP: ^bool) -> u16 {
	if dbIDP != nil {
		for i in 0 ..< DB_SLOTS {
			if rawptr(&world.db.dbs[i]) == dbP {dbIDP[0] = u32(i + 1)}
		}
	}
	return 0
}

PrefGetAppPreferences :: proc(creator: u32, id: u16, prefs: rawptr, prefsSize: [^]u16, saved: bool) -> i16 {
	d := &world.db.dbs[0]
	if !d.used || !d.has_rec {return -1}
	n := min(i32(prefsSize[0]), d.size)
	mem.copy(prefs, &d.data[0], int(n))
	prefsSize[0] = u16(n)
	return 1
}

PrefSetAppPreferences :: proc(creator: u32, id: u16, version: i16, prefs: rawptr, prefsSize: u16, saved: bool) {
	d := &world.db.dbs[0]
	d.used = true
	copy(d.name[:], PREFS_NAME)
	d.has_rec = true
	d.size = min(i32(prefsSize), DB_RECORD_CAP)
	mem.copy(&d.data[0], prefs, int(d.size))
	world.db.dirty = true
}

// ---------------------------------------------------------------- system

FtrGet :: proc "contextless" (creator: u32, featureNum: u16, valueP: [^]u32) -> u16 {
	if valueP != nil {valueP[0] = 0x05000000} // OS 5.0
	return 0
}
TimGetTicks :: proc "contextless" () -> u32 {return world.ticks}
TimGetSeconds :: proc "contextless" () -> u32 {return world.ticks / 100}
TimDateTimeToSeconds :: proc "contextless" (dt: ^DateTimeType) -> u32 {return 0}
SysTicksPerSecond :: proc "contextless" () -> u16 {return 100}
AppLaunchWithCommand :: proc "contextless" (dbType: u32, launchCode: u16, commandPBP: rawptr) -> u16 {return 0}
GrfSetState :: proc "contextless" (capsLock, numLock, upperShift: bool) {}
WinScreenMode :: proc "contextless" (op: i32, w, h, depth: [^]u32, color: ^bool) -> u16 {return 0}

// Palm's SysRandom: 0..sysRandomMax (0x7FFF). A non-zero seed reseeds.
SysRandom :: proc "contextless" (newSeed: i32) -> i16 {
	if newSeed != 0 {world.rand = u32(newSeed)}
	world.rand = world.rand * 1103515245 + 12345
	return i16((world.rand >> 16) & 0x7FFF)
}

_ :: runtime
