// Pictures. The original pictures are Alexander Lawrence's and are not used;
// every bitmap id gets its size from tools/bitmap_sizes.txt and, until real
// art exists, a placeholder drawn here.
package game

Art_Size :: struct {
	id, w, h: i32,
}

ART_SIZES := [?]Art_Size{
	{1000, 32, 32}, {1100, 160, 160}, {1200, 5, 5}, {1300, 7, 7}, {1400, 7, 7}, {1500, 160, 160},
	{1600, 7, 7}, {1700, 5, 5}, {1800, 160, 160}, {1900, 5, 5}, {2000, 7, 7}, {2100, 7, 7},
	{2200, 19, 16}, {2300, 19, 16}, {2600, 27, 26}, {2700, 27, 26}, {3000, 27, 22}, {3100, 27, 22},
	{3200, 31, 26}, {3300, 31, 26}, {3400, 27, 26}, {3500, 27, 26}, {3600, 31, 30}, {3700, 31, 30},
	{3800, 40, 34}, {3900, 40, 34}, {4000, 44, 38}, {4100, 44, 38}, {4200, 40, 36}, {4300, 40, 36},
	{4400, 44, 40}, {4500, 44, 40}, {4600, 50, 40}, {4700, 50, 40}, {4800, 54, 44}, {4900, 54, 44},
	{5000, 50, 40}, {5100, 50, 40}, {5200, 54, 44}, {5300, 54, 44}, {5400, 60, 47}, {5500, 60, 47},
	{5600, 64, 51}, {5700, 64, 51}, {5800, 60, 48}, {5900, 60, 48}, {6000, 64, 52}, {6100, 64, 52},
	{6200, 49, 40}, {6300, 49, 40}, {6600, 22, 23}, {6700, 22, 23}, {6800, 52, 43}, {6900, 52, 43},
	{7000, 34, 42}, {7100, 34, 42}, {7200, 38, 46}, {7300, 38, 46}, {7400, 49, 40}, {7500, 49, 40},
	{7800, 46, 19}, {7900, 46, 19}, {9500, 12, 12}, {9600, 12, 12}, {9700, 12, 12}, {9800, 12, 12},
	{9900, 12, 12}, {11000, 9, 9}, {11100, 9, 9}, {12000, 160, 160},
}

art_size :: proc "contextless" (id: i32) -> (i32, i32) {
	for a in ART_SIZES {
		if a.id == id {return a.w, a.h}
	}
	return 16, 16
}

// Placeholder pictures: stars and markers as small shapes, ships as hulls.
art_draw :: proc "contextless" (id: i32, x, y: i32, w_in, h_in: i32) {
	w, h := art_size(id)
	switch id {
	case 1200, 1900: // system dot (unvisited / visited)
		c: u8 = COL_BLACK
		for yy in i32(1) ..< 4 {for xx in i32(1) ..< 4 {pset(x + xx, y + yy, c)}}
		pset(x + 2, y, c); pset(x + 2, y + 4, c); pset(x, y + 2, c); pset(x + 4, y + 2, c)
		if id == 1900 {pset(x + 2, y + 2, COL_WHITE)}
	case 1300, 2000, 1400, 2100: // current system / short range system
		for yy in i32(0) ..< 7 {
			for xx in i32(0) ..< 7 {
				dx, dy := xx - 3, yy - 3
				d := dx * dx + dy * dy
				if d <= 9 && d >= 4 {pset(x + xx, y + yy, COL_BLACK)}
				if (id == 1400 || id == 1300) && d < 4 {pset(x + xx, y + yy, COL_BLACK)}
			}
		}
	case 1600, 1700: // wormhole
		for yy in i32(0) ..< h {
			for xx in i32(0) ..< w {
				if (xx + yy) % 2 == 0 {pset(x + xx, y + yy, 13)}
			}
		}
	case 1500, 1100, 1800, 12000: // full-screen pictures
		draw_placeholder_screen(id, x, y)
	case 9500 ..= 9900, 11000, 11100: // encounter icons
		frame_rect(x, y, w, h, 1, COL_BLACK)
		ch := "?"
		switch id {
		case 9500: ch = "P"
		case 9600: ch = "C"
		case 9700: ch = "T"
		case 9800: ch = "A"
		case 9900: ch = "!"
		case 11000, 11100: ch = "*"
		}
		draw_text(ch, x + 3, y, boldFont, COL_BLACK, COL_WHITE, false)
	case:
		draw_placeholder_ship(id, x, y, w, h)
	}
}

draw_placeholder_ship :: proc "contextless" (id: i32, x, y, w, h: i32) {
	damaged := (id / 100) % 2 == 1 && id < 7400 || id == 7500 || id == 7900
	shielded := false
	switch id % 400 {
	case 0, 100: shielded = false
	case 200, 300: shielded = true
	}
	if id >= 2200 && id < 3000 {shielded = false; damaged = id % 400 == 300 || id == 2300 || id == 2700}
	cx, cy := w / 2, h / 2
	rx, ry := max(w / 2 - 3, 2), max(h / 2 - 3, 2)
	if shielded {
		rx -= 2
		ry -= 2
	}
	body: u8 = 6 if damaged else 13
	for yy in i32(0) ..< h {
		for xx in i32(0) ..< w {
			dx := f32(xx - cx) / f32(rx)
			dy := f32(yy - cy) / f32(ry)
			d := dx * dx + dy * dy
			if d <= 1.0 {
				c := body
				if d > 0.7 {c = COL_BLACK}
				pset(x + xx, y + yy, c)
			}
			if shielded {
				ex := f32(xx - cx) / f32(rx + 2)
				ey := f32(yy - cy) / f32(ry + 2)
				e := ex * ex + ey * ey
				if e <= 1.0 && e > 0.8 && d > 1.0 {pset(x + xx, y + yy, 12)}
			}
		}
	}
}

draw_placeholder_screen :: proc "contextless" (id: i32, x, y: i32) {
	fill(x, y, 160, 160, 2)
	// a few stars
	s: u32 = u32(id) * 2654435761
	for _ in 0 ..< 60 {
		s = s * 1103515245 + 12345
		sx := i32((s >> 8) % 160)
		s = s * 1103515245 + 12345
		sy := i32((s >> 8) % 160)
		pset(x + sx, y + sy, 7 if s & 1 == 0 else 0)
	}
	title := "SPACE PEDDLERS"
	sub := "of SPLORR!!"
	switch id {
	case 1100: title = "RETIRED"; sub = ""
	case 1800: title = "UTOPIA"; sub = ""
	case 12000: title = "DESTROYED"; sub = ""
	}
	tw := text_width(title, boldFont)
	draw_text(title, x + (160 - tw) / 2, y + 60, boldFont, 10, 2, false)
	sw := text_width(sub, stdFont)
	draw_text(sub, x + (160 - sw) / 2, y + 74, stdFont, 11, 2, false)
}
