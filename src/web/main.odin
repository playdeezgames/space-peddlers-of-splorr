#+build js
// The browser side: exports called by web/index.html.
package main

import "base:runtime"
import game "../game"

rgba: [game.FB_W * game.FB_H]u32
load_buf: []u8
ctx: runtime.Context

main :: proc() {
	ctx = context
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {return true}

@(export)
platform_alloc :: proc "c" (n: i32) -> rawptr {
	context = ctx
	load_buf = make([]u8, int(n))
	return raw_data(load_buf)
}

@(export)
platform_init :: proc "c" (seed: u32, saved_len: i32) {
	context = ctx
	saved: []u8
	if saved_len > 0 && len(load_buf) >= int(saved_len) {saved = load_buf[:saved_len]}
	game.init(seed, saved)
	free_all(context.temp_allocator)
}

@(export)
platform_tap :: proc "c" (x, y: i32) {
	context = ctx
	game.tap(x, y)
	free_all(context.temp_allocator)
}

@(export)
platform_key :: proc "c" (chr: i32) {
	context = ctx
	game.key(u16(chr))
	free_all(context.temp_allocator)
}

@(export)
platform_menu :: proc "c" () {
	context = ctx
	game.menu()
	free_all(context.temp_allocator)
}

@(export)
platform_tick :: proc "c" (ms: i32) {
	context = ctx
	game.tick(ms)
	free_all(context.temp_allocator)
}

@(export)
platform_frame :: proc "c" () -> rawptr {
	context = ctx
	fb := game.screen()
	for i in 0 ..< len(fb) {
		c := game.PALETTE[fb[i] & 15]
		// bytes R,G,B,A in memory
		rgba[i] = 0xFF000000 | ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)
	}
	return &rgba[0]
}

@(export)
platform_db_ptr :: proc "c" () -> rawptr {
	context = ctx
	return raw_data(game.db_bytes())
}

@(export)
platform_db_len :: proc "c" () -> i32 {
	context = ctx
	return i32(len(game.db_bytes()))
}

@(export)
platform_db_dirty :: proc "c" () -> i32 {
	context = ctx
	return 1 if game.db_dirty() else 0
}

@(export)
platform_db_clean :: proc "c" () {
	context = ctx
	game.db_clean()
}
