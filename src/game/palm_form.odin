// Palm OS emulation, part 3: forms, controls, fields, lists and their drawing.
package game

Obj_Kind :: enum u8 {
	Title,
	Label,
	Button,
	Field,
	Checkbox,
	List,
	Popup_Trigger,
	Popup_List,
	Gadget,
	Bitmap,
	Graffiti,
	Repeat_Button,
	Push_Button,
	Selector,
}

Font_Id :: enum u8 {
	Standard,
	Bold,
	Large,
	Symbol,
	Large_Bold,
}

Alert_Kind :: enum u8 {
	Information,
	Confirmation,
	Warning,
	Error,
}

Obj_Def :: struct {
	kind:          Obj_Kind,
	id:            u16,
	x, y, w, h:    i16,
	font:          Font_Id,
	text:          string,
	usable:        bool,
	frame:         bool,
	bold_frame:    bool,
	editable:      bool,
	max_chars:     u16,
	numeric:       bool,
	group:         u16,
	selected:      bool,
	items_first:   u16,
	items_count:   u16,
	visible_items: u16,
	popup_list:    u16,
	bitmap:        u16,
}

Form_Def :: struct {
	id:             u16,
	x, y, w, h:     i16,
	modal:          bool,
	help_id:        u16,
	menu_id:        u16,
	default_button: u16,
	title:          string,
	first, count:   u16,
}

Alert_Def :: struct {
	id:             u16,
	kind:           Alert_Kind,
	help_id:        u16,
	default_button: u16,
	title:          string,
	message:        string,
	first, count:   u16,
}

String_Def :: struct {
	id:   u16,
	text: string,
}

String_List_Def :: struct {
	id, first, count: u16,
}

Menu_Item_Def :: struct {
	text: string,
	key:  rune,
}

Menu_Def :: struct {
	id:           u16,
	title:        string,
	first, count: u16,
}

Menu_Bar_Def :: struct {
	id:    u16,
	menus: [4]u16,
	count: u16,
}

Obj_State :: struct {
	kind:        Obj_Kind,
	id:          u16,
	x, y, w, h:  i32,
	font:        i32,
	usable:      bool,
	frame:       i32, // ButtonFrameType: 0 none, 1 standard, 2 bold, 3 rectangle
	value:       i16,
	selection:   i16,
	label:       [LABEL_CAP]u8,
	handle:      MemHandle, // field text handle
	max_chars:   i32,
	numeric:     bool,
	editable:    bool,
	items_first: i32,
	items_count: i32,
	visible:     i32,
	popup_list:  u16,
	bitmap:      u16,
	group:       u16,
}

ControlType :: Obj_State
FieldType :: Obj_State
ListType :: Obj_State

FormType :: struct {
	used:      bool,
	def:       i32,
	id:        u16,
	x, y, w, h: i32,
	modal:     bool,
	menu_id:   u16,
	help_id:   u16,
	default_button: u16,
	title:     [LABEL_CAP]u8,
	objs:      [MAX_OBJS]Obj_State,
	nobj:      i32,
	handler:   FormEventHandlerType,
	focus:     i32,
	drawn:     bool,
	prev_active: i32,
}

noFrame :: 0
standardButtonFrame :: 1
boldButtonFrame :: 2
rectangleButtonFrame :: 3

form_def_index :: proc(id: u16) -> i32 {
	for d, i in FORM_DEFS {
		if d.id == id {return i32(i)}
	}
	return -1
}

form_index :: proc "contextless" (f: ^FormType) -> i32 {
	for i in 0 ..< MAX_FORMS {
		if &world.forms[i] == f {return i32(i)}
	}
	return -1
}

set_label :: proc "contextless" (dst: []u8, s: string) {
	n := min(len(s), len(dst) - 1)
	for i in 0 ..< n {dst[i] = s[i]}
	dst[n] = 0
}

FrmInitForm :: proc(rscID: u16) -> ^FormType {
	di := form_def_index(rscID)
	if di < 0 {panic("FrmInitForm: unknown form")}
	slot := -1
	for i in 0 ..< MAX_FORMS {
		if !world.forms[i].used {slot = i; break}
	}
	if slot < 0 {panic("FrmInitForm: too many forms")}
	f := &world.forms[slot]
	f^ = {}
	d := FORM_DEFS[di]
	f.used = true
	f.def = di
	f.id = d.id
	f.x, f.y, f.w, f.h = i32(d.x), i32(d.y), i32(d.w), i32(d.h)
	f.modal = d.modal
	f.menu_id = d.menu_id
	f.help_id = d.help_id
	f.default_button = d.default_button
	f.focus = -1
	f.prev_active = -1
	set_label(f.title[:], d.title)
	for k in 0 ..< i32(d.count) {
		od := OBJ_DEFS[i32(d.first) + k]
		o := &f.objs[f.nobj]
		f.nobj += 1
		o.kind = od.kind
		o.id = od.id
		o.x, o.y, o.w, o.h = i32(od.x) + f.x, i32(od.y) + f.y, i32(od.w), i32(od.h)
		if od.kind == .Popup_List {o.x, o.y = i32(od.x), i32(od.y)}
		switch od.font {
		case .Standard, .Symbol: o.font = stdFont
		case .Bold: o.font = boldFont
		case .Large: o.font = largeFont
		case .Large_Bold: o.font = largeBoldFont
		}
		o.usable = od.usable
		o.frame = noFrame
		if od.frame {o.frame = boldButtonFrame if od.bold_frame else standardButtonFrame}
		o.value = 1 if od.selected else 0
		o.selection = -1
		set_label(o.label[:], od.text)
		o.max_chars = i32(od.max_chars)
		o.numeric = od.numeric
		o.editable = od.editable
		o.items_first = i32(od.items_first)
		o.items_count = i32(od.items_count)
		o.visible = i32(od.visible_items)
		o.popup_list = od.popup_list
		o.bitmap = od.bitmap
		o.group = od.group
		if od.kind == .List && od.items_count > 0 {o.selection = 0}
	}
	// popup lists are only shown while popped up
	for i in 0 ..< f.nobj {
		o := &f.objs[i]
		if o.kind == .Popup_List {
			for j in 0 ..< f.nobj {
				if f.objs[j].kind == .List && f.objs[j].id == o.popup_list {
					f.objs[j].usable = false
				}
			}
		}
	}
	return f
}

FrmDeleteForm :: proc "contextless" (f: ^FormType) {
	if f == nil {return}
	idx := form_index(f)
	if world.active == idx {world.active = f.prev_active}
	f.used = false
}

FrmCloseAllForms :: proc "contextless" () {
	for i in 0 ..< MAX_FORMS {world.forms[i].used = false}
	world.active = -1
}

FrmGetActiveForm :: proc "contextless" () -> ^FormType {
	if world.active < 0 {return nil}
	return &world.forms[world.active]
}

FrmGetActiveFormID :: proc "contextless" () -> u16 {
	f := FrmGetActiveForm()
	return f.id if f != nil else 0
}

FrmSetActiveForm :: proc "contextless" (f: ^FormType) {
	world.active = form_index(f)
}

FrmGetFormPtr :: proc "contextless" (formId: u16) -> ^FormType {
	for i in 0 ..< MAX_FORMS {
		if world.forms[i].used && world.forms[i].id == formId {return &world.forms[i]}
	}
	return nil
}

FrmSetEventHandler :: proc "contextless" (f: ^FormType, handler: FormEventHandlerType) {
	f.handler = handler
}

FrmSetMenu :: proc "contextless" (f: ^FormType, menuRscID: u16) {
	f.menu_id = menuRscID
}

FrmGetObjectIndex :: proc "contextless" (f: ^FormType, objID: u16) -> u16 {
	for i in 0 ..< f.nobj {
		if f.objs[i].id == objID && f.objs[i].kind != .Popup_List {return u16(i)}
	}
	return 0xFFFF
}

FrmGetObjectPtr :: proc "contextless" (f: ^FormType, objIndex: u16) -> rawptr {
	if i32(objIndex) >= f.nobj {return nil}
	return &f.objs[objIndex]
}

obj_by_id :: proc "contextless" (f: ^FormType, id: u16) -> ^Obj_State {
	i := FrmGetObjectIndex(f, id)
	if i == 0xFFFF {return nil}
	return &f.objs[i]
}

FrmShowObject :: proc(f: ^FormType, objIndex: u16) {
	if i32(objIndex) >= f.nobj {return}
	o := &f.objs[objIndex]
	if o.usable {return}
	o.usable = true
	if f.drawn {draw_object(f, o)}
}

FrmHideObject :: proc(f: ^FormType, objIndex: u16) {
	if i32(objIndex) >= f.nobj {return}
	o := &f.objs[objIndex]
	if !o.usable {return}
	o.usable = false
	if f.drawn {erase_object(f, o)}
}

FrmCopyLabel :: proc(f: ^FormType, labelID: u16, newLabel: cstring) {
	o := obj_by_id(f, labelID)
	if o == nil {return}
	if o.usable && f.drawn {erase_object(f, o)}
	set_label(o.label[:], cs(newLabel))
	if o.usable && f.drawn {draw_object(f, o)}
}

FrmSetTitle :: proc(f: ^FormType, newTitle: cstring) {
	set_label(f.title[:], cs(newTitle))
	if f.drawn {draw_title(f)}
}
FrmCopyTitle :: proc(f: ^FormType, newTitle: cstring) {FrmSetTitle(f, newTitle)}
FrmGetTitle :: proc "contextless" (f: ^FormType) -> cstring {return cstring(&f.title[0])}

FrmSetFocus :: proc "contextless" (f: ^FormType, fieldIndex: u16) {
	f.focus = i32(fieldIndex) if fieldIndex != 0xFFFF else -1
}

CtlSetLabel :: proc(c: ^ControlType, newLabel: cstring) {
	f := form_of_obj(c)
	if f != nil && c.usable && f.drawn {erase_object(f, c)}
	set_label(c.label[:], cs(newLabel))
	if f != nil && c.usable && f.drawn {draw_object(f, c)}
}
CtlGetLabel :: proc "contextless" (c: ^ControlType) -> cstring {return cstring(&c.label[0])}
CtlSetValue :: proc(c: ^ControlType, v: i16) {
	c.value = v
	f := form_of_obj(c)
	if f != nil && c.usable && f.drawn {draw_object(f, c)}
}
CtlGetValue :: proc "contextless" (c: ^ControlType) -> i16 {return c.value}
CtlDrawControl :: proc(c: ^ControlType) {
	f := form_of_obj(c)
	if f != nil {draw_object(f, c)}
}
CtlShowControl :: proc(c: ^ControlType) {
	f := form_of_obj(c)
	c.usable = true
	if f != nil && f.drawn {draw_object(f, c)}
}

LstSetSelection :: proc "contextless" (l: ^ListType, item: i16) {l.selection = item}
LstGetSelection :: proc "contextless" (l: ^ListType) -> i16 {return l.selection}

form_of_obj :: proc "contextless" (o: ^Obj_State) -> ^FormType {
	for i in 0 ..< MAX_FORMS {
		f := &world.forms[i]
		if !f.used {continue}
		base := uintptr(&f.objs[0])
		p := uintptr(o)
		if p >= base && p < base + size_of(f.objs) {return f}
	}
	return nil
}

// Field text lives in the Palm handle (as in the original, GetField reads it).
FldSetTextHandle :: proc(fld: ^FieldType, h: MemHandle) {
	fld.handle = h
	if h != nil {
		set_label(fld.label[:], cs(cstring(h)))
	} else {
		fld.label[0] = 0
	}
	f := form_of_obj(fld)
	if f != nil && fld.usable && f.drawn {draw_object(f, fld)}
}

field_store :: proc(fld: ^FieldType) {
	if fld.handle != nil {
		StrCopy(cstring(fld.handle), cstring(&fld.label[0]))
	}
}

// ---------------------------------------------------------------- drawing

obj_bounds :: proc "contextless" (o: ^Obj_State) -> Rect {
	#partial switch o.kind {
	case .Label:
		return {o.x, o.y, text_width(buf_str(o.label[:]), o.font), FONT_LINE}
	case .Button, .Repeat_Button, .Push_Button, .Selector:
		return {o.x - 1, o.y - 1, o.w + 2, o.h + 2}
	case .Bitmap:
		w, h := art_size(i32(o.bitmap))
		return {o.x, o.y, w, h}
	}
	return {o.x, o.y, o.w, o.h}
}

erase_object :: proc "contextless" (f: ^FormType, o: ^Obj_State) {
	b := obj_bounds(o)
	fill(b.x, b.y, b.w, b.h, COL_WHITE)
}

draw_object :: proc "contextless" (f: ^FormType, o: ^Obj_State) {
	if !o.usable {return}
	s := buf_str(o.label[:])
	#partial switch o.kind {
	case .Label:
		draw_text(s, o.x, o.y, o.font, COL_BLACK, COL_WHITE)
	case .Button, .Repeat_Button, .Push_Button, .Selector:
		if o.frame == noFrame && len(s) == 0 {return} // invisible tap area (e.g. over a title)
		fill(o.x, o.y, o.w, o.h, COL_WHITE)
		switch o.frame {
		case standardButtonFrame: frame_rect(o.x - 1, o.y - 1, o.w + 2, o.h + 2, 1, COL_BLACK)
		case boldButtonFrame:
			frame_rect(o.x - 1, o.y - 1, o.w + 2, o.h + 2, 1, COL_BLACK)
			frame_rect(o.x, o.y, o.w, o.h, 1, COL_BLACK)
		case rectangleButtonFrame: frame_rect(o.x - 1, o.y - 1, o.w + 2, o.h + 2, 0, COL_BLACK)
		}
		tw := text_width(s, o.font)
		tx := o.x + (o.w - tw) / 2
		ty := o.y + (o.h - FONT_LINE) / 2
		if o.kind == .Push_Button && o.value != 0 {
			fill(o.x, o.y, o.w, o.h, COL_BLACK)
			draw_text(s, tx, ty, o.font, COL_WHITE, COL_BLACK, false)
		} else {
			draw_text(s, tx, ty, o.font, COL_BLACK, COL_WHITE, false)
		}
	case .Checkbox:
		fill(o.x, o.y, o.w, o.h, COL_WHITE)
		by := o.y + (o.h - 9) / 2
		frame_rect(o.x, by, 9, 9, 0, COL_BLACK)
		if o.value != 0 {
			line(o.x + 2, by + 4, o.x + 3, by + 6, COL_BLACK)
			line(o.x + 3, by + 6, o.x + 7, by + 1, COL_BLACK)
			line(o.x + 2, by + 3, o.x + 3, by + 5, COL_BLACK)
		}
		draw_text(s, o.x + 12, o.y + (o.h - FONT_LINE) / 2, o.font, COL_BLACK, COL_WHITE)
	case .Popup_Trigger:
		fill(o.x, o.y, o.w, o.h, COL_WHITE)
		ty := o.y + (o.h - 7) / 2 + 2
		for r in 0 ..< i32(4) {
			for xx in o.x + r ..< o.x + 7 - r {pset(xx, ty + r, COL_BLACK)}
		}
		draw_text(s, o.x + 10, o.y + (o.h - FONT_LINE) / 2, o.font, COL_BLACK, COL_WHITE)
	case .Field:
		fill(o.x, o.y, o.w, o.h, COL_WHITE)
		draw_text(s, o.x, o.y, o.font, COL_BLACK, COL_WHITE)
		if o.editable {
			for xx := o.x; xx < o.x + o.w; xx += 2 {pset(xx, o.y + FONT_LINE, COL_BLACK)}
			if f.focus >= 0 && &f.objs[f.focus] == o {
				cx := o.x + text_width(s, o.font)
				for yy in o.y + 1 ..< o.y + FONT_LINE {pset(cx, yy, COL_BLACK)}
			}
		}
	case .List:
		draw_list(o)
	case .Bitmap:
		art_draw(i32(o.bitmap), o.x, o.y, 0, 0)
	}
}

draw_list :: proc "contextless" (o: ^Obj_State) {
	fill(o.x, o.y, o.w, o.visible * FONT_LINE, COL_WHITE)
	frame_rect(o.x - 1, o.y - 1, o.w + 2, o.visible * FONT_LINE + 2, 0, COL_BLACK)
	for i in 0 ..< min(o.visible, o.items_count) {
		s := RSRC_POOL[o.items_first + i]
		y := o.y + i * FONT_LINE
		if i32(o.selection) == i {
			fill(o.x, y, o.w, FONT_LINE, COL_BLACK)
			draw_text(s, o.x + 2, y, o.font, COL_WHITE, COL_BLACK, false)
		} else {
			draw_text(s, o.x + 2, y, o.font, COL_BLACK, COL_WHITE, false)
		}
	}
}

TITLE_H :: 11

draw_title :: proc "contextless" (f: ^FormType) {
	t := buf_str(f.title[:])
	if f.modal {
		fill(f.x, f.y, f.w, TITLE_H, COL_BLACK)
		tw := text_width(t, boldFont)
		draw_text(t, f.x + (f.w - tw) / 2, f.y, boldFont, COL_WHITE, COL_BLACK, false)
	} else if len(t) > 0 {
		tw := text_width(t, boldFont)
		fill(0, 0, tw + 6, TITLE_H, COL_BLACK)
		pset(0, 0, COL_WHITE)
		pset(tw + 5, 0, COL_WHITE)
		draw_text(t, 3, 0, boldFont, COL_WHITE, COL_BLACK, false)
		for x in i32(0) ..< SCREEN_W {pset(x, TITLE_H - 1, COL_BLACK)}
	}
}

FrmDrawForm :: proc(f: ^FormType) {
	if f.modal {
		fill(f.x, f.y, f.w, f.h, COL_WHITE)
		frame_rect(f.x - 1, f.y - 1, f.w + 2, f.h + 2, 0, COL_BLACK)
		frame_rect(f.x - 2, f.y - 2, f.w + 4, f.h + 4, 1, COL_BLACK)
	} else {
		fill(f.x, f.y, f.w, f.h, COL_WHITE)
	}
	draw_title(f)
	f.drawn = true
	for i in 0 ..< f.nobj {
		o := &f.objs[i]
		if o.kind == .List && !o.usable {continue}
		draw_object(f, o)
	}
}

FrmEraseForm :: proc "contextless" (f: ^FormType) {
	fill(f.x, f.y, f.w, f.h, COL_WHITE)
	f.drawn = false
}

// The object under (x, y), topmost (last) first.
hit_object :: proc "contextless" (f: ^FormType, x, y: i32) -> i32 {
	for i := f.nobj - 1; i >= 0; i -= 1 {
		o := &f.objs[i]
		if !o.usable {continue}
		#partial switch o.kind {
		case .Button, .Repeat_Button, .Push_Button, .Selector, .Checkbox, .Popup_Trigger, .Field, .List:
			b := Rect{o.x, o.y, o.w, o.h}
			if o.kind == .List {b.h = o.visible * FONT_LINE}
			if x >= b.x && y >= b.y && x < b.x + b.w && y < b.y + b.h {return i}
		}
	}
	return -1
}
