// Palm OS emulation, part 4: events, the replay engine and the modal UI
// (alerts, help, dialogs, popup lists, menus).
//
// Space Trader's C code blocks inside FrmAlert, FrmDoDialog and friends. A
// browser frame loop cannot block, so the game runs as a deterministic
// function of its inputs: a *transaction* starts from a snapshot of `world`
// and replays the inputs logged so far. When a blocking call needs an input
// that has not happened yet, the run records the screen as it is at that
// moment and stops caring about the rest (it will be thrown away). The next
// tap or key is appended to the log and the transaction is replayed from the
// snapshot. When a run reaches the top-level loop with nothing left to do, the
// transaction commits and the next input starts a new one.
package game

import "core:mem"

nilEvent :: 0
penDownEvent :: 1
penUpEvent :: 2
penMoveEvent :: 3
keyDownEvent :: 4
winEnterEvent :: 5
winExitEvent :: 6
ctlEnterEvent :: 7
ctlExitEvent :: 8
ctlSelectEvent :: 9
ctlRepeatEvent :: 10
lstEnterEvent :: 11
lstSelectEvent :: 12
lstExitEvent :: 13
popSelectEvent :: 14
fldEnterEvent :: 15
fldHeightChangedEvent :: 16
fldChangedEvent :: 17
tblEnterEvent :: 18
tblSelectEvent :: 19
daySelectEvent :: 20
menuEvent :: 21
appStopEvent :: 22
frmLoadEvent :: 23
frmOpenEvent :: 24
frmGotoEvent :: 25
frmUpdateEvent :: 26
frmSaveEvent :: 27
frmCloseEvent :: 28
frmTitleEnterEvent :: 29
frmTitleSelectEvent :: 30

evtWaitForever :: -1
noPreferenceFound :: -1
errNone :: 0
sysErrRomIncompatible :: 0x0501
sysAppLaunchCmdNormalLaunch :: 0
sysAppLaunchFlagNewGlobals :: 4
sysAppLaunchFlagUIApp :: 8
sysFtrCreator :: 0x70737973
sysFtrNumROMVersion :: 1
bitmapRsc :: 0x54626d70
dmModeReadWrite :: 3
dmModeReadOnly :: 1
dmHdrAttrBackup :: 8
sysFileCDefaultApp :: 0
sysROMStageRelease :: 3
chrBackspace :: 0x08
chrLineFeed :: 0x0A
chrPageUp :: 0x0B
chrPageDown :: 0x0C
vchrMenu :: 0x0105
vchrHard1 :: 0x0204
vchrHard2 :: 0x0205
vchrHard3 :: 0x0206
vchrHard4 :: 0x0207
hard1Chr :: 0x0204
hard2Chr :: 0x0205
hard3Chr :: 0x0206
hard4Chr :: 0x0207
grfTempShiftUpper :: 2
winScreenModeGetSupportsColor :: 0
winScreenModeGetSupportedDepths :: 1
winScreenModeSet :: 2
winScreenModeSetToDefaults :: 3
appFileCreator :: 0x53547261
appPrefID :: 0
winPaint :: 0

EventType :: struct {
	eType:    i32,
	penDown:  bool,
	tapCount: i16,
	screenX:  i16,
	screenY:  i16,
	data:     struct {
		ctlSelect: struct {
			controlID: u16,
			pControl:  ^ControlType,
			on:        bool,
		},
		keyDown:   struct {
			chr:       u16,
			keyCode:   u16,
			modifiers: u16,
		},
		menu:      struct {
			itemID: u16,
		},
		frmLoad:   struct {
			formID: u16,
		},
		frmOpen:   struct {
			formID: u16,
		},
		frmUpdate: struct {
			formID:     u16,
			updateCode: u16,
		},
		popSelect: struct {
			controlID:      u16,
			controlP:       ^ControlType,
			listP:          ^ListType,
			selection:      i16,
			priorSelection: i16,
		},
		lstSelect: struct {
			listID:    u16,
			pList:     ^ListType,
			selection: i16,
		},
	},
}

Input_Kind :: enum u8 {
	Start,
	Tap,
	Key,
	Tick,
}

Input :: struct {
	kind: Input_Kind,
	x, y: i16,
	chr:  u16,
}

Replay :: struct {
	log:      [dynamic]Input,
	pos:      int,
	waiting:  bool,
	depth:    int,
	base:     World, // snapshot the transaction starts from
	fb_shown: [FB_W * FB_H]u8,
	started:  bool,
	guard:    int,
}

replay: Replay

// ---------------------------------------------------------------- queue

EvtAddEventToQueue :: proc "contextless" (ev: ^EventType) {
	if world.q_len >= MAX_EVENTS {return}
	world.queue[(world.q_head + world.q_len) % MAX_EVENTS] = ev^
	world.q_len += 1
}

post :: proc "contextless" (etype: i32) {
	ev: EventType
	ev.eType = etype
	EvtAddEventToQueue(&ev)
}

queue_pop :: proc "contextless" () -> (EventType, bool) {
	if world.q_len == 0 {return {}, false}
	ev := world.queue[world.q_head]
	world.q_head = (world.q_head + 1) % MAX_EVENTS
	world.q_len -= 1
	return ev, true
}

// The next logged input. Inside a blocking call (depth > 0) running out of
// inputs means we must wait for the player.
next_input :: proc() -> (Input, bool) {
	if replay.waiting {return {}, false}
	if replay.pos < len(replay.log) {
		inp := replay.log[replay.pos]
		replay.pos += 1
		return inp, true
	}
	if replay.depth > 0 {
		replay.waiting = true
		replay.fb_shown = world.fb
	}
	return {}, false
}

input_event :: proc(inp: Input) -> EventType {
	ev: EventType
	switch inp.kind {
	case .Tap:
		ev.eType = penDownEvent
		ev.penDown = true
		ev.screenX = inp.x
		ev.screenY = inp.y
	case .Key:
		ev.eType = keyDownEvent
		ev.data.keyDown.chr = inp.chr
	case .Tick, .Start:
		ev.eType = nilEvent
	}
	return ev
}

// Next event for a nested loop: queued events first, then logged input.
next_event :: proc() -> (EventType, bool) {
	if ev, ok := queue_pop(); ok {return ev, true}
	inp, ok := next_input()
	if !ok {return {}, false}
	return input_event(inp), true
}

// ---------------------------------------------------------------- default form handling

FrmDispatchEvent :: proc(ev: ^EventType) -> bool {
	f := FrmGetActiveForm()
	if f == nil {return false}
	if f.handler != nil && f.handler(ev) {return true}
	return FrmHandleEvent(f, ev)
}

FrmHandleEvent :: proc(f: ^FormType, ev: ^EventType) -> bool {
	switch ev.eType {
	case frmOpenEvent, frmUpdateEvent:
		FrmDrawForm(f)
		return true
	case frmCloseEvent:
		FrmEraseForm(f)
		FrmDeleteForm(f)
		return true
	case penDownEvent:
		x, y := i32(ev.screenX), i32(ev.screenY)
		i := hit_object(f, x, y)
		if i < 0 {return false}
		o := &f.objs[i]
		#partial switch o.kind {
		case .Button, .Repeat_Button, .Selector:
			flash_button(f, o)
			post_ctl(o)
		case .Push_Button:
			o.value = 1
			draw_object(f, o)
			post_ctl(o)
		case .Checkbox:
			o.value = 0 if o.value != 0 else 1
			draw_object(f, o)
			post_ctl(o)
		case .Popup_Trigger:
			popup_list(f, o)
		case .Field:
			if o.editable {
				old := f.focus
				f.focus = i
				if old >= 0 && old != i {draw_object(f, &f.objs[old])}
				draw_object(f, o)
			}
		case .List:
			sel := (y - o.y) / FONT_LINE
			if sel >= 0 && sel < o.items_count {
				o.selection = i16(sel)
				draw_object(f, o)
				e: EventType
				e.eType = lstSelectEvent
				e.data.lstSelect.listID = o.id
				e.data.lstSelect.pList = o
				e.data.lstSelect.selection = i16(sel)
				EvtAddEventToQueue(&e)
			}
		}
		return true
	case keyDownEvent:
		if f.focus >= 0 {
			return field_key(f, &f.objs[f.focus], ev.data.keyDown.chr)
		}
	}
	return false
}

post_ctl :: proc(o: ^Obj_State) {
	e: EventType
	e.eType = ctlSelectEvent
	e.data.ctlSelect.controlID = o.id
	e.data.ctlSelect.pControl = o
	e.data.ctlSelect.on = o.value != 0
	EvtAddEventToQueue(&e)
}

flash_button :: proc(f: ^FormType, o: ^Obj_State) {
	// Palm inverts a button while the pen is down; the screen we show is
	// captured at the next wait, so this is only visible in replays' logic.
}

field_key :: proc(f: ^FormType, o: ^Obj_State, chr: u16) -> bool {
	s := buf_str(o.label[:])
	n := len(s)
	if chr == chrBackspace {
		if n > 0 {o.label[n - 1] = 0}
	} else if chr >= 32 && chr < 127 {
		if o.numeric && (chr < '0' || chr > '9') {return true}
		if o.max_chars > 0 && n >= int(o.max_chars) {return true}
		if n < LABEL_CAP - 1 {
			o.label[n] = u8(chr)
			o.label[n + 1] = 0
		}
	} else {
		return false
	}
	field_store(o)
	draw_object(f, o)
	return true
}

// ---------------------------------------------------------------- blocking UI

save_behind :: proc() -> [FB_W * FB_H]u8 {return world.fb}

after_modal :: proc() {
	post(winEnterEvent)
}

begin_block :: proc() {replay.depth += 1}
end_block :: proc() {replay.depth -= 1}

ALERT_BUTTON_H :: 12

Alert_Layout :: struct {
	x, y, w, h: i32,
	lines:      [16]string,
	nlines:     i32,
	bx:         [4]i32,
	bw:         [4]i32,
	by:         i32,
	nbuttons:   i32,
	text_x:     i32,
	help:       bool,
}

alert_def :: proc(id: u16) -> ^Alert_Def {
	for &a in ALERT_DEFS {
		if a.id == id {return &a}
	}
	return nil
}

// Word-wrap into lines of at most `width` pixels (stdFont).
wrap :: proc(s: string, width: i32, out: []string) -> i32 {
	n: i32 = 0
	start := 0
	for start < len(s) && int(n) < len(out) {
		w: i32 = 0
		i := start
		last_space := -1
		for i < len(s) && s[i] != '\n' {
			a := glyph_hadv(s[i], stdFont)
			if w + a > width * 2 {break}
			if s[i] == ' ' {last_space = i}
			w += a
			i += 1
		}
		end := i
		next := i
		if i < len(s) && s[i] == '\n' {
			next = i + 1
		} else if i < len(s) {
			if last_space > start {
				end = last_space
				next = last_space + 1
			}
		}
		out[n] = s[start:end]
		n += 1
		start = next
	}
	return n
}

expand_alert_text :: proc(msg: string, s1, s2, s3: cstring) -> string {
	b := make([dynamic]u8, context.temp_allocator)
	for i := 0; i < len(msg); i += 1 {
		if msg[i] == '^' && i + 1 < len(msg) && msg[i + 1] >= '1' && msg[i + 1] <= '3' {
			r := [3]cstring{s1, s2, s3}[msg[i + 1] - '1']
			append(&b, cs(r))
			i += 1
			continue
		}
		append(&b, msg[i])
	}
	return string(b[:])
}

layout_alert :: proc(a: ^Alert_Def, text: string) -> Alert_Layout {
	L: Alert_Layout
	L.w = 156
	L.x = 2
	L.text_x = L.x + 26
	L.nlines = wrap(text, L.w - 30, L.lines[:])
	L.nbuttons = i32(a.count)
	text_h := max(L.nlines * FONT_LINE, 24)
	L.h = TITLE_H + 4 + text_h + 4 + ALERT_BUTTON_H + 5
	L.y = SCREEN_H - 2 - L.h
	if L.y < 2 {L.y = 2}
	L.by = L.y + L.h - 4 - ALERT_BUTTON_H
	bx := L.x + 4
	for i in 0 ..< L.nbuttons {
		label := RSRC_POOL[i32(a.first) + i]
		bw := max(text_width(label, stdFont) + 10, 36)
		L.bx[i] = bx
		L.bw[i] = bw
		bx += bw + 6
	}
	L.help = a.help_id != 0
	return L
}

draw_alert :: proc(a: ^Alert_Def, L: ^Alert_Layout) {
	fill(L.x, L.y, L.w, L.h, COL_WHITE)
	frame_rect(L.x - 1, L.y - 1, L.w + 2, L.h + 2, 0, COL_BLACK)
	frame_rect(L.x - 2, L.y - 2, L.w + 4, L.h + 4, 1, COL_BLACK)
	fill(L.x, L.y, L.w, TITLE_H, COL_BLACK)
	tw := text_width(a.title, boldFont)
	draw_text(a.title, L.x + (L.w - tw) / 2, L.y, boldFont, COL_WHITE, COL_BLACK, false)
	if L.help {
		// the "i" button at the right of the title bar
		cx := L.x + L.w - 10
		fill(cx, L.y + 1, 9, 9, COL_WHITE)
		draw_text("i", cx + 3, L.y - 1, boldFont, COL_BLACK, COL_WHITE, false)
	}
	draw_alert_icon(a.kind, L.x + 5, L.y + TITLE_H + 5)
	for i in 0 ..< L.nlines {
		draw_text(L.lines[i], L.text_x, L.y + TITLE_H + 4 + i * FONT_LINE, stdFont, COL_BLACK, COL_WHITE, false)
	}
	for i in 0 ..< L.nbuttons {
		label := RSRC_POOL[i32(a.first) + i]
		frame_rect(L.bx[i] - 1, L.by - 1, L.bw[i] + 2, ALERT_BUTTON_H + 2, 1, COL_BLACK)
		lw := text_width(label, stdFont)
		draw_text(label, L.bx[i] + (L.bw[i] - lw) / 2, L.by, stdFont, COL_BLACK, COL_WHITE, false)
	}
}

draw_alert_icon :: proc(kind: Alert_Kind, x, y: i32) {
	// 16x16 icons in the Palm style: circle "i", "?", "!" triangle, stop sign
	switch kind {
	case .Information, .Confirmation:
		for yy in i32(0) ..< 16 {
			for xx in i32(0) ..< 16 {
				dx, dy := xx * 2 - 15, yy * 2 - 15
				if dx * dx + dy * dy <= 225 {pset(x + xx, y + yy, COL_BLACK)}
			}
		}
		ch := "i" if kind == .Information else "?"
		draw_text(ch, x + 6, y + 1, boldFont, COL_WHITE, COL_BLACK, false)
	case .Warning:
		for yy in i32(0) ..< 15 {
			half := yy / 2
			for xx in 7 - half ..= 8 + half {pset(x + xx, y + yy, COL_BLACK)}
		}
		draw_text("!", x + 6, y + 3, boldFont, COL_WHITE, COL_BLACK, false)
	case .Error:
		fill(x + 3, y, 10, 16, COL_BLACK)
		fill(x, y + 3, 16, 10, COL_BLACK)
		fill(x + 1, y + 1, 14, 14, COL_BLACK)
		draw_text("x", x + 5, y + 2, boldFont, COL_WHITE, COL_BLACK, false)
	}
}

FrmAlert :: proc(alertId: u16) -> u16 {
	return FrmCustomAlert(alertId, "", "", "")
}

FrmCustomAlert :: proc(alertId: u16, s1, s2, s3: cstring) -> u16 {
	if replay.waiting {return 0xFFFF}
	a := alert_def(alertId)
	if a == nil {return 0}
	text := expand_alert_text(a.message, s1, s2, s3)
	L := layout_alert(a, text)
	saved := save_behind()
	draw_alert(a, &L)
	begin_block()
	defer end_block()
	for {
		inp, ok := next_input()
		if !ok {return 0xFFFF}
		if inp.kind == .Key {
			if inp.chr == chrLineFeed || inp.chr == ' ' {
				world.fb = saved
				after_modal()
				return a.default_button
			}
			continue
		}
		if inp.kind != .Tap {continue}
		x, y := i32(inp.x), i32(inp.y)
		if L.help && y >= L.y && y < L.y + TITLE_H && x >= L.x + L.w - 14 {
			FrmHelp(a.help_id)
			if replay.waiting {return 0xFFFF}
			continue
		}
		for i in 0 ..< L.nbuttons {
			if x >= L.bx[i] - 2 && x < L.bx[i] + L.bw[i] + 2 && y >= L.by - 2 && y < L.by + ALERT_BUTTON_H + 2 {
				world.fb = saved
				after_modal()
				return u16(i)
			}
		}
	}
}

// The Palm "Tips" dialog: scrollable help text with a Done button.
FrmHelp :: proc(helpMsgId: u16) {
	if replay.waiting {return}
	text := string_by_id(i32(helpMsgId))
	lines := make([]string, 400, context.temp_allocator)
	X, Y, W, H :: 2, 2, 156, 156
	n := wrap(text, W - 8, lines)
	per_page: i32 = (H - TITLE_H - 22) / FONT_LINE
	top: i32 = 0
	saved := save_behind()
	begin_block()
	defer end_block()
	for {
		fill(X, Y, W, H, COL_WHITE)
		frame_rect(X - 1, Y - 1, W + 2, H + 2, 0, COL_BLACK)
		frame_rect(X - 2, Y - 2, W + 4, H + 4, 1, COL_BLACK)
		fill(X, Y, W, TITLE_H, COL_BLACK)
		tw := text_width("Tips", boldFont)
		draw_text("Tips", X + (W - tw) / 2, Y, boldFont, COL_WHITE, COL_BLACK, false)
		for i in 0 ..< per_page {
			if top + i >= n {break}
			draw_text(lines[top + i], X + 4, Y + TITLE_H + 2 + i * FONT_LINE, stdFont, COL_BLACK, COL_WHITE, false)
		}
		by: i32 = Y + H - 16
		frame_rect(X + 4 - 1, by - 1, 36 + 2, 12 + 2, 1, COL_BLACK)
		draw_text("Done", X + 4 + (36 - text_width("Done", stdFont)) / 2, by, stdFont, COL_BLACK, COL_WHITE, false)
		can_up := top > 0
		can_down := top + per_page < n
		draw_arrow(X + W - 22, by + 2, true, can_up)
		draw_arrow(X + W - 11, by + 2, false, can_down)
		inp, ok := next_input()
		if !ok {return}
		if inp.kind == .Key {
			switch inp.chr {
			case chrPageUp: if can_up {top = max(0, top - per_page + 1)}
			case chrPageDown: if can_down {top += per_page - 1}
			case chrLineFeed, ' ':
				world.fb = saved
				after_modal()
				return
			}
			continue
		}
		if inp.kind != .Tap {continue}
		x, y := i32(inp.x), i32(inp.y)
		if y >= by - 2 && y < by + 14 {
			if x >= X + 2 && x < X + 44 {
				world.fb = saved
				after_modal()
				return
			}
			if x >= X + W - 24 && x < X + W - 13 && can_up {top = max(0, top - per_page + 1)}
			if x >= X + W - 13 && can_down {top += per_page - 1}
		} else if y > Y + TITLE_H && y < by - 2 {
			// tapping the text pages too
			if y < Y + H / 2 && can_up {
				top = max(0, top - per_page + 1)
			} else if can_down {
				top += per_page - 1
			}
		}
	}
}

draw_arrow :: proc(x, y: i32, up: bool, enabled: bool) {
	c: u8 = COL_BLACK if enabled else PAL_GREY
	for r in i32(0) ..< 5 {
		yy := y + (r if up else 4 - r)
		for xx in x + 4 - r ..= x + 4 + r {pset(xx, yy, c)}
	}
}

PAL_GREY :: 7

FrmDoDialog :: proc(f: ^FormType) -> u16 {
	if replay.waiting {return 0}
	saved := save_behind()
	prev := world.active
	f.prev_active = prev
	world.active = form_index(f)
	FrmDrawForm(f)
	if f.handler != nil {
		e: EventType
		e.eType = frmOpenEvent
		e.data.frmOpen.formID = f.id
		f.handler(&e)
	}
	post(winEnterEvent)
	begin_block()
	result: u16 = 0
	loop: for {
		ev, ok := next_event()
		if !ok {break}
		if ev.eType == penDownEvent {
			x, y := i32(ev.screenX), i32(ev.screenY)
			if x < f.x || y < f.y || x >= f.x + f.w || y >= f.y + f.h {continue}
		}
		if ev.eType == keyDownEvent && ev.data.keyDown.chr == chrLineFeed && f.default_button != 0 {
			o := obj_by_id(f, f.default_button)
			if o != nil {
				post_ctl(o)
				continue
			}
		}
		handled := f.handler != nil && f.handler(&ev)
		if replay.waiting {break}
		if !handled {
			if ev.eType == ctlSelectEvent {
				o := obj_by_id(f, ev.data.ctlSelect.controlID)
				if o != nil && (o.kind == .Button || o.kind == .Repeat_Button) {
					result = o.id
					break loop
				}
			}
			FrmHandleEvent(f, &ev)
		}
		if replay.waiting {break}
	}
	end_block()
	if replay.waiting {return 0}
	// drop events meant for the dialog
	world.q_len = 0
	world.active = prev
	f.drawn = false
	world.fb = saved
	after_modal()
	return result
}

popup_list :: proc(f: ^FormType, trigger: ^Obj_State) {
	lst: ^Obj_State = nil
	for i in 0 ..< f.nobj {
		if f.objs[i].kind == .List && f.objs[i].id == trigger.popup_list {lst = &f.objs[i]}
	}
	if lst == nil {return}
	saved := save_behind()
	prior := lst.selection
	lst.usable = true
	draw_list(lst)
	begin_block()
	defer end_block()
	inp, ok := next_input()
	lst.usable = false
	if !ok {return}
	world.fb = saved
	if inp.kind != .Tap {return}
	x, y := i32(inp.x), i32(inp.y)
	if x < lst.x || x >= lst.x + lst.w || y < lst.y || y >= lst.y + lst.visible * FONT_LINE {return}
	sel := (y - lst.y) / FONT_LINE
	if sel >= lst.items_count {return}
	lst.selection = i16(sel)
	set_label(trigger.label[:], RSRC_POOL[lst.items_first + sel])
	draw_object(f, trigger)
	e: EventType
	e.eType = popSelectEvent
	e.data.popSelect.controlID = trigger.id
	e.data.popSelect.controlP = trigger
	e.data.popSelect.listP = lst
	e.data.popSelect.selection = i16(sel)
	e.data.popSelect.priorSelection = prior
	EvtAddEventToQueue(&e)
}

MenuEraseStatus :: proc "contextless" (menuP: rawptr) {}
SysHandleEvent :: proc "contextless" (ev: ^EventType) -> bool {return false}
MenuHandleEvent :: proc "contextless" (menuP: rawptr, ev: ^EventType, err: [^]u16) -> bool {return false}

menu_bar_def :: proc(id: u16) -> ^Menu_Bar_Def {
	for &b in MENU_BAR_DEFS {
		if b.id == id {return &b}
	}
	return nil
}

menu_def :: proc(id: u16) -> ^Menu_Def {
	for &m in MENU_DEFS {
		if m.id == id {return &m}
	}
	return nil
}

// The Palm menu bar: titles across the top, one menu dropped down.
run_menu :: proc(f: ^FormType) {
	if f == nil || f.menu_id == 0 {return}
	bar := menu_bar_def(f.menu_id)
	if bar == nil {return}
	saved := save_behind()
	cur: i32 = 0
	begin_block()
	defer end_block()
	for {
		// bar
		fill(0, 0, SCREEN_W, 13, COL_WHITE)
		frame_rect(0, 0, SCREEN_W, 13, 0, COL_BLACK)
		tx := [4]i32{}
		x: i32 = 3
		for i in 0 ..< i32(bar.count) {
			m := menu_def(bar.menus[i])
			tx[i] = x
			w := text_width(m.title, boldFont) + 6
			if i == cur {
				fill(x - 2, 1, w, 11, COL_BLACK)
				draw_text(m.title, x + 1, 1, boldFont, COL_WHITE, COL_BLACK, false)
			} else {
				draw_text(m.title, x + 1, 1, boldFont, COL_BLACK, COL_WHITE, false)
			}
			x += w + 2
		}
		m := menu_def(bar.menus[cur])
		mw: i32 = 0
		for k in 0 ..< i32(m.count) {
			it := MENU_ITEM_DEFS[i32(m.first) + k]
			w := text_width(it.text, stdFont) + 24
			mw = max(mw, w)
		}
		mx := min(tx[cur] - 2, SCREEN_W - mw - 2)
		my: i32 = 13
		mh: i32 = 0
		for k in 0 ..< i32(m.count) {
			it := MENU_ITEM_DEFS[i32(m.first) + k]
			mh += 5 if it.text == "-" else FONT_LINE
		}
		fill(mx, my, mw, mh + 2, COL_WHITE)
		frame_rect(mx, my - 1, mw, mh + 3, 0, COL_BLACK)
		iy := my + 1
		item_y: [16]i32
		for k in 0 ..< i32(m.count) {
			it := MENU_ITEM_DEFS[i32(m.first) + k]
			item_y[k] = iy
			if it.text == "-" {
				for xx := mx + 2; xx < mx + mw - 2; xx += 2 {pset(xx, iy + 2, COL_BLACK)}
				iy += 5
				continue
			}
			draw_text(it.text, mx + 4, iy, stdFont, COL_BLACK, COL_WHITE, false)
			if it.key != 0 {
				key: [1]u8 = {u8(it.key)}
				draw_text(string(key[:]), mx + mw - 10, iy, stdFont, COL_BLACK, COL_WHITE, false)
				for yy in iy + 2 ..< iy + 9 {pset(mx + mw - 13, yy, COL_BLACK)}
			}
			iy += FONT_LINE
		}
		inp, ok := next_input()
		if !ok {return}
		chosen: i32 = -1
		if inp.kind == .Key {
			c := lower(u8(inp.chr))
			if inp.chr == vchrMenu || inp.chr == 27 {
				world.fb = saved
				return
			}
			for mi in 0 ..< i32(bar.count) {
				mm := menu_def(bar.menus[mi])
				for k in 0 ..< i32(mm.count) {
					it := MENU_ITEM_DEFS[i32(mm.first) + k]
					if it.key != 0 && lower(u8(it.key)) == c {chosen = i32(mm.id) + k}
				}
			}
			if chosen < 0 {continue}
		} else if inp.kind == .Tap {
			x2, y2 := i32(inp.x), i32(inp.y)
			if y2 < 13 {
				for i in 0 ..< i32(bar.count) {
					mm := menu_def(bar.menus[i])
					w := text_width(mm.title, boldFont) + 6
					if x2 >= tx[i] - 2 && x2 < tx[i] - 2 + w {cur = i}
				}
				world.fb = saved
				continue
			}
			if x2 >= mx && x2 < mx + mw && y2 >= my && y2 < my + mh + 2 {
				for k in 0 ..< i32(m.count) {
					it := MENU_ITEM_DEFS[i32(m.first) + k]
					if it.text == "-" {continue}
					if y2 >= item_y[k] && y2 < item_y[k] + FONT_LINE {chosen = i32(m.id) + k}
				}
				if chosen < 0 {continue}
			} else {
				world.fb = saved
				return
			}
		} else {
			continue
		}
		world.fb = saved
		e: EventType
		e.eType = menuEvent
		e.data.menu.itemID = u16(chosen)
		EvtAddEventToQueue(&e)
		return
	}
}

// ---------------------------------------------------------------- the top level

// One pass of the original AppEventLoop body for one event.
dispatch_top :: proc(ev: ^EventType) {
	f := FrmGetActiveForm()
	if ev.eType == keyDownEvent && ev.data.keyDown.chr == vchrMenu {
		run_menu(f)
	} else if ev.eType == penDownEvent && f != nil && !f.modal && f.menu_id != 0 && ev.screenY < TITLE_H &&
	   i32(ev.screenX) < text_width(buf_str(f.title[:]), boldFont) + 6 {
		run_menu(f)
	} else if ev.eType == nilEvent && ev.data.keyDown.chr == 0xFFFF {
		app_start()
	} else if ev.eType == nilEvent {
		if g.Continuous && (g.AutoAttack || g.AutoFlee) && g.CurForm == EncounterForm {
			EncounterFormHandleEvent(ev)
		}
	} else {
		if !AppHandleEvent(ev) {FrmDispatchEvent(ev)}
	}
	if g.CurForm != EncounterForm {
		g.AutoAttack = false
		g.AutoFlee = false
	}
}

// Replay the current transaction from its snapshot. Returns true when it
// committed (no blocking call is waiting).
run_transaction :: proc() -> bool {
	world = replay.base
	replay.pos = 0
	replay.waiting = false
	replay.depth = 0
	for {
		ev, ok := queue_pop()
		if !ok {
			inp, ok2 := next_input()
			if !ok2 {break}
			ev = input_event(inp)
			if inp.kind == .Start {ev.data.keyDown.chr = 0xFFFF}
		}
		dispatch_top(&ev)
		free_all(context.temp_allocator)
		if replay.waiting {break}
	}
	if replay.waiting {return false}
	replay.fb_shown = world.fb
	clear(&replay.log)
	replay.base = world
	return true
}

// Feed one input. Returns true when the game state committed.
feed :: proc(inp: Input) -> bool {
	append(&replay.log, inp)
	committed := run_transaction()
	if committed {
		autosave()
	}
	return committed
}

autosave :: proc() {
	SaveGame(0)
	replay.base.db = world.db
}

// Is the player in the middle of a blocking dialog?
in_modal :: proc() -> bool {return len(replay.log) > 0}

_ :: mem
