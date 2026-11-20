// Palm OS emulation, part 2: the 160x160 screen, fonts and drawing calls.
package game

COL_WHITE :: 0
COL_BLACK :: 1

// Palette shared by the UI and the art. Index 0 and 1 are the Palm paper
// and ink; the rest are for pictures (see art.odin).
PALETTE := [16]u32{
	0xFFFFFF, 0x000000, 0x1D2B53, 0x7E2553, 0x008751, 0xAB5236, 0x5F574F, 0xC2C3C7,
	0xFFF1E8, 0xFF004D, 0xFFA300, 0xFFEC27, 0x00E436, 0x29ADFF, 0x83769C, 0xFF77A8,
}

stdFont :: 0
boldFont :: 1
largeFont :: 2
largeBoldFont :: 7

FONT_LINE :: 11

BitmapType :: struct {
	width:  i16,
	height: i16,
	id:     i32,
}

PointType :: struct {
	x, y: i16,
}
RectangleType :: struct {
	topLeft: PointType,
	extent:  PointType,
}
DateTimeType :: struct {
	second, minute, hour, day, month, year, weekDay: i16,
}

screen_clip :: proc "contextless" () -> Rect {
	if world.clip.w <= 0 {return {0, 0, SCREEN_W, SCREEN_H}}
	return world.clip
}

// Drawing origin: Palm draws into the active window, which for a modal
// dialog is the dialog's rectangle. Form objects are stored in screen
// coordinates, so only the Win* calls the game makes add this.
org :: proc "contextless" () -> (i32, i32) {
	f := FrmGetActiveForm()
	if f != nil && f.modal {return f.x, f.y}
	return 0, 0
}

// A pixel in the framebuffer's double-density coordinates.
hpset :: #force_inline proc "contextless" (hx, hy: i32, c: u8) {
	cl := screen_clip()
	if hx < cl.x * 2 || hy < cl.y * 2 || hx >= (cl.x + cl.w) * 2 || hy >= (cl.y + cl.h) * 2 {return}
	if hx < 0 || hy < 0 || hx >= FB_W || hy >= FB_H {return}
	world.fb[hy * FB_W + hx] = c
}

// A pixel in Palm (160x160) coordinates: a 2x2 block.
pset :: #force_inline proc "contextless" (x, y: i32, c: u8) {
	hpset(x * 2, y * 2, c)
	hpset(x * 2 + 1, y * 2, c)
	hpset(x * 2, y * 2 + 1, c)
	hpset(x * 2 + 1, y * 2 + 1, c)
}

fill :: proc "contextless" (x, y, w, h: i32, c: u8) {
	for yy in y ..< y + h {
		for xx in x ..< x + w {
			pset(xx, yy, c)
		}
	}
}

// Rounded rectangle outline, corner radius r (0..2).
frame_rect :: proc "contextless" (x, y, w, h: i32, r: i32, c: u8) {
	for xx in x + r ..< x + w - r {
		pset(xx, y, c)
		pset(xx, y + h - 1, c)
	}
	for yy in y + r ..< y + h - r {
		pset(x, yy, c)
		pset(x + w - 1, yy, c)
	}
	if r > 0 {
		pset(x + 1, y + 1, c)
		pset(x + w - 2, y + 1, c)
		pset(x + 1, y + h - 2, c)
		pset(x + w - 2, y + h - 2, c)
	}
}

// ---- fonts: m6x11 at double density; widths reported in Palm units

glyph_hadv :: proc "contextless" (ch: u8, font: i32) -> i32 {
	a: i32 = 5
	if ch >= 32 && ch <= 126 {
		a = i32(FONT_ADV[ch - 32])
	} else if ch == 0xA9 {
		a = 3 * i32(FONT_ADV['c' - 32]) + i32(FONT_ADV['(' - 32])
	}
	if font == boldFont || font == largeBoldFont {a += 1}
	return a
}

draw_glyph :: proc "contextless" (ch: u8, hx, hy: i32, font: i32, col: u8) {
	if ch == 0xA9 {
		x := hx
		for c in "(c)" {
			draw_glyph(u8(c), x, hy, font, col)
			x += glyph_hadv(u8(c), font)
		}
		return
	}
	if ch < 32 || ch > 126 {return}
	rows := &FONT_ROWS[ch - 32]
	bold := font == boldFont || font == largeBoldFont
	for r in 0 ..< i32(FONT_H) {
		bits := rows[r]
		for cx in 0 ..< i32(10) {
			if bits & (1 << u32(cx)) != 0 {
				hpset(hx + cx, hy + 5 + r, col)
				if bold {hpset(hx + cx + 1, hy + 5 + r, col)}
			}
		}
	}
}

text_hwidth :: proc "contextless" (s: string, font: i32) -> i32 {
	w: i32 = 0
	for i in 0 ..< len(s) {
		w += glyph_hadv(s[i], font)
	}
	return w
}

text_width :: proc "contextless" (s: string, font: i32) -> i32 {
	return (text_hwidth(s, font) + 1) / 2
}

// For FntCharsInWidth: the width of one character in Palm units is not a
// whole number, so measure prefixes.
draw_text :: proc "contextless" (s: string, x, y: i32, font: i32, ink: u8, paper: u8, erase := true) {
	if erase {fill(x, y, text_width(s, font), FONT_LINE, paper)}
	hx := x * 2
	for i in 0 ..< len(s) {
		draw_glyph(s[i], hx, y * 2, font, ink)
		hx += glyph_hadv(s[i], font)
	}
}

c_slice :: proc "contextless" (chars: cstring, n: i16) -> string {
	if chars == nil || n <= 0 {return ""}
	return string(cidx(chars)[:n])
}

FntSetFont :: proc "contextless" (font: i32) -> i32 {
	old := world.font
	world.font = font
	return old
}
FntLineHeight :: proc "contextless" () -> i16 {return FONT_LINE}
FntCharsWidth :: proc "contextless" (chars: cstring, n: i16) -> i16 {
	return i16(text_width(c_slice(chars, n), world.font))
}

// Palm semantics: on entry *width is the room and *length the characters; on
// exit *length is how many fit (stopping before a newline), *width their width.
FntCharsInWidth :: proc "contextless" (str: cstring, widthP: [^]i16, lengthP: [^]i16, fits: ^bool) {
	p := cidx(str)
	room := i32(widthP[0]) * 2
	n := i32(lengthP[0])
	w: i32 = 0
	i: i32 = 0
	for i < n && p[i] != 0 && p[i] != '\n' {
		a := glyph_hadv(p[i], world.font)
		if w + a > room {break}
		w += a
		i += 1
	}
	fits^ = i >= n || p[i] == 0
	lengthP[0] = i16(i)
	widthP[0] = i16((w + 1) / 2)
}

WinDrawChars :: proc "contextless" (chars: cstring, n: i16, x: i16, y: i16) {
	ox, oy := org()
	draw_text(c_slice(chars, n), i32(x) + ox, i32(y) + oy, world.font, COL_BLACK, COL_WHITE)
}
WinDrawInvertedChars :: proc "contextless" (chars: cstring, n: i16, x: i16, y: i16) {
	ox, oy := org()
	draw_text(c_slice(chars, n), i32(x) + ox, i32(y) + oy, world.font, COL_WHITE, COL_BLACK)
}

line :: proc "contextless" (x1, y1, x2, y2: i32, c: u8) {
	dx := abs(x2 - x1)
	dy := -abs(y2 - y1)
	sx: i32 = 1 if x1 < x2 else -1
	sy: i32 = 1 if y1 < y2 else -1
	err := dx + dy
	x, y := x1, y1
	for {
		pset(x, y, c)
		if x == x2 && y == y2 {break}
		e2 := 2 * err
		if e2 >= dy {err += dy; x += sx}
		if e2 <= dx {err += dx; y += sy}
	}
}

WinDrawLine :: proc "contextless" (x1, y1, x2, y2: i16) {
	ox, oy := org()
	line(i32(x1) + ox, i32(y1) + oy, i32(x2) + ox, i32(y2) + oy, COL_BLACK)
}
WinEraseLine :: proc "contextless" (x1, y1, x2, y2: i16) {
	ox, oy := org()
	line(i32(x1) + ox, i32(y1) + oy, i32(x2) + ox, i32(y2) + oy, COL_WHITE)
}

rect_of :: proc "contextless" (r: ^RectangleType) -> Rect {
	ox, oy := org()
	return {i32(r.topLeft.x) + ox, i32(r.topLeft.y) + oy, i32(r.extent.x), i32(r.extent.y)}
}

WinDrawRectangle :: proc "contextless" (r: ^RectangleType, corner: u16) {
	rr := rect_of(r)
	fill(rr.x, rr.y, rr.w, rr.h, COL_BLACK)
}
WinEraseRectangle :: proc "contextless" (r: ^RectangleType, corner: u16) {
	rr := rect_of(r)
	fill(rr.x, rr.y, rr.w, rr.h, COL_WHITE)
}
WinDrawRectangleFrame :: proc "contextless" (frame: u16, r: ^RectangleType) {
	rr := rect_of(r)
	frame_rect(rr.x - 1, rr.y - 1, rr.w + 2, rr.h + 2, 0, COL_BLACK)
}
WinSetClip :: proc "contextless" (r: ^RectangleType) {world.clip = rect_of(r)}
WinResetClip :: proc "contextless" () {world.clip = {}}

WinDrawBitmap :: proc "contextless" (bmp: ^BitmapType, x: i16, y: i16) {
	if bmp == nil {return}
	ox, oy := org()
	art_draw(bmp.id, i32(x) + ox, i32(y) + oy, i32(bmp.width), i32(bmp.height))
}

BmpGetDimensions :: proc "contextless" (bmp: ^BitmapType, w: [^]i16, h: [^]i16, rowBytes: [^]u16) {
	if w != nil {w[0] = bmp.width}
	if h != nil {h[0] = bmp.height}
}

bitmaps: [dynamic]BitmapType

DmGetResource :: proc(type: u32, resID: u16) -> MemHandle {
	w, h := art_size(i32(resID))
	b := new(BitmapType)
	b^ = {i16(w), i16(h), i32(resID)}
	return b
}
DmReleaseResource :: proc "contextless" (h: MemHandle) -> u16 {return 0}
