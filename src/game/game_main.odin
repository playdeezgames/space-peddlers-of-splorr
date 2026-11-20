// Hand-written replacements for the parts of Merchant.c and Draw.c that talk
// to Palm OS internals (see OVERRIDES in tools/transpile.py), and the entry
// points the platform calls.
package game

// Math.c's integer square root (named `sqrt` there).
sqrt :: proc(a: i32) -> i32 {
	i: i32 = 0
	for i * i < a {i += 1}
	if i > 0 {
		if (i * i - a) > (a - (i - 1) * (i - 1)) {i -= 1}
	}
	return i
}

RectangularButton :: proc(frmP: ^FormType, Nr: i32) -> ^ControlType {
	idx := FrmGetObjectIndex(frmP, u16(Nr))
	cp := cast(^ControlType)FrmGetObjectPtr(frmP, idx)
	if cp != nil {cp.frame = rectangleButtonFrame}
	return cp
}

GetBitmapWidth :: proc(b: ^BitmapType) -> i32 {return i32(b.width)}
GetBitmapHeight :: proc(b: ^BitmapType) -> i32 {return i32(b.height)}

AppStop :: proc() {SaveGame(0)}

// MerchantPilotMain up to the event loop.
app_start :: proc() {
	g.SystemBmp = DmGetResource(bitmapRsc, SystemBitmapFamily)
	g.SystemBmpPtr = cast(^BitmapType)MemHandleLock(g.SystemBmp)
	g.CurrentSystemBmp = DmGetResource(bitmapRsc, CurrentSystemBitmapFamily)
	g.CurrentSystemBmpPtr = cast(^BitmapType)MemHandleLock(g.CurrentSystemBmp)
	g.ShortRangeSystemBmp = DmGetResource(bitmapRsc, ShortRangeSystemBitmapFamily)
	g.ShortRangeSystemBmpPtr = cast(^BitmapType)MemHandleLock(g.ShortRangeSystemBmp)
	g.WormholeBmp = DmGetResource(bitmapRsc, WormholeBitmapFamily)
	g.WormholeBmpPtr = cast(^BitmapType)MemHandleLock(g.WormholeBmp)
	g.SmallWormholeBmp = DmGetResource(bitmapRsc, SmallWormholeBitmapFamily)
	g.SmallWormholeBmpPtr = cast(^BitmapType)MemHandleLock(g.SmallWormholeBmp)
	g.VisitedSystemBmp = DmGetResource(bitmapRsc, VisitedSystemBitmapFamily)
	g.VisitedSystemBmpPtr = cast(^BitmapType)MemHandleLock(g.VisitedSystemBmp)
	g.CurrentVisitedSystemBmp = DmGetResource(bitmapRsc, CurrentVisitedSystemBitmapFamily)
	g.CurrentVisitedSystemBmpPtr = cast(^BitmapType)MemHandleLock(g.CurrentVisitedSystemBmp)
	g.VisitedShortRangeSystemBmp = DmGetResource(bitmapRsc, VisitedShortRangeSystemBitmapFamily)
	g.VisitedShortRangeSystemBmpPtr = cast(^BitmapType)MemHandleLock(g.VisitedShortRangeSystemBmp)
	for i in 0 ..< i32(MAXSHIPTYPE + EXTRASHIPS) {
		g.ShipBmp[i] = DmGetResource(bitmapRsc, u16(FleaBitmapFamily + i * 400))
		g.ShipBmpPtr[i] = cast(^BitmapType)MemHandleLock(g.ShipBmp[i])
		g.DamagedShipBmp[i] = DmGetResource(bitmapRsc, u16(FleaDamagedBitmapFamily + i * 400))
		g.DamagedShipBmpPtr[i] = cast(^BitmapType)MemHandleLock(g.DamagedShipBmp[i])
		if Shiptype[i].ShieldSlots <= 0 {
			g.ShieldedShipBmp[i] = g.ShipBmp[i]
			g.ShieldedShipBmpPtr[i] = g.ShipBmpPtr[i]
			g.DamagedShieldedShipBmp[i] = g.DamagedShipBmp[i]
			g.DamagedShieldedShipBmpPtr[i] = g.DamagedShipBmpPtr[i]
		} else {
			g.ShieldedShipBmp[i] = DmGetResource(bitmapRsc, u16(FireflyShieldedBitmapFamily + (i - 2) * 400))
			g.ShieldedShipBmpPtr[i] = cast(^BitmapType)MemHandleLock(g.ShieldedShipBmp[i])
			g.DamagedShieldedShipBmp[i] = DmGetResource(bitmapRsc, u16(FireflyShDamBitmapFamily + (i - 2) * 400))
			g.DamagedShieldedShipBmpPtr[i] = cast(^BitmapType)MemHandleLock(g.DamagedShieldedShipBmp[i])
		}
	}
	for i in 0 ..< i32(5) {
		g.IconBmp[i] = DmGetResource(bitmapRsc, u16(PirateBitmapFamily + i * 100))
		g.IconBmpPtr[i] = cast(^BitmapType)MemHandleLock(g.IconBmp[i])
	}
	AppStart()
	if g.IdentifyStartup {
		FrmCustomAlert(IdentifyStartupAlert, cstring(&g.NameCommander[0]), "", "")
	}
	FrmGotoForm(u16(g.CurForm))
}

FrmGotoForm :: proc(formId: u16) {
	f := FrmGetActiveForm()
	if f != nil {post(frmCloseEvent)}
	e: EventType
	e.eType = frmLoadEvent
	e.data.frmLoad.formID = formId
	EvtAddEventToQueue(&e)
	e = {}
	e.eType = frmOpenEvent
	e.data.frmOpen.formID = formId
	EvtAddEventToQueue(&e)
}

// Called once by the platform. `seed` seeds Palm's random generator and
// `saved_db` (may be empty) restores the persisted databases.
init :: proc(seed: u32, saved_db: []u8) {
	world = {}
	clear(&replay.log)
	replay.pos = 0
	replay.waiting = false
	replay.depth = 0
	world.active = -1
	globals_init()
	world.rand = seed | 1
	if len(saved_db) == size_of(Db_Store) {
		copy((cast([^]u8)&world.db)[:size_of(Db_Store)], saved_db)
	}
	world.db.dirty = false
	replay.base = world
	feed({kind = .Start})
}

// ---------------------------------------------------------------- platform API

tap :: proc(x, y: i32) {
	if x < 0 || y < 0 || x >= SCREEN_W || y >= SCREEN_H {return}
	feed({kind = .Tap, x = i16(x), y = i16(y)})
}

key :: proc(chr: u16) {
	feed({kind = .Key, chr = chr})
}

menu :: proc() {key(vchrMenu)}

tick_accum: i32

// Advance the clock. Between transactions the Palm tick counter moves on;
// in continuous attack/flee the encounter steps about every 0.7 seconds.
tick :: proc(ms: i32) {
	if in_modal() {return}
	replay.base.ticks += u32(max(ms, 0) / 10)
	b := &replay.base.g
	if b.Continuous && (b.AutoAttack || b.AutoFlee) && b.CurForm == EncounterForm {
		tick_accum += ms
		if tick_accum >= 700 {
			tick_accum = 0
			feed({kind = .Tick})
		}
	} else {
		tick_accum = 0
	}
}

// The screen to show: the moment a dialog started waiting, or the committed state.
screen :: proc() -> []u8 {return replay.fb_shown[:]}

db_bytes :: proc() -> []u8 {return (cast([^]u8)&replay.base.db)[:size_of(Db_Store)]}
db_dirty :: proc() -> bool {return replay.base.db.dirty}
db_clean :: proc() {replay.base.db.dirty = false; world.db.dirty = false}
