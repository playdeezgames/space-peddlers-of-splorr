#+build !js
package game

import "core:fmt"
import "core:os"
import "core:testing"

dump :: proc(name: string) {
	fb := screen()
	b := make([dynamic]u8, context.temp_allocator)
	hdr := fmt.tprintf("P6\n%d %d\n255\n", FB_W, FB_H)
	append(&b, hdr)
	for p in fb {
		c := PALETTE[p & 15]
		append(&b, u8(c >> 16), u8(c >> 8), u8(c))
	}
	os.make_directory("build/shots")
	_ = os.write_entire_file(fmt.tprintf("build/shots/%s.ppm", name), b[:])
}

@(test)
smoke_new_game :: proc(t: ^testing.T) {
	init(12345, nil)
	dump("00-start")
	tap(80, 80) // main form: any tap starts a new game
	dump("01-after-tap")
	key(chrLineFeed)
	dump("02-after-enter")
	for y in ([]i32{81, 96, 112, 126}) {
		for _ in 0 ..< 4 {tap(101, y)} // spend the 16 skill points
	}
	tap(79, 149) // OK
	dump("03-system-info")
	key('b')
	dump("04-buy-cargo")
}

// Random play: taps anywhere, shortcut letters, Enter, digits and the menu.
soak :: proc(seed: u64, steps: int, tag: string) {
	init(u32(seed), nil)
	s := seed * 6364136223846793005 + 1442695040888963407
	rnd :: proc(s: ^u64, n: int) -> int {
		s^ = s^ * 6364136223846793005 + 1442695040888963407
		return int((s^ >> 33) % u64(n))
	}
	KEYS := "bsyeqpkicgwh0123456789"
	for i in 0 ..< steps {
		r := rnd(&s, 100)
		switch {
		case r < 80:
			tap(i32(rnd(&s, 160)), i32(rnd(&s, 160)))
		case r < 90:
			key(u16(KEYS[rnd(&s, len(KEYS))]))
		case r < 95:
			key(chrLineFeed)
		case r < 97:
			menu()
		case:
			tick(800)
		}
		free_all(context.temp_allocator)
		if i % 800 == 0 {dump(fmt.tprintf("soak-%s-%05d", tag, i))}
	}
	dump(fmt.tprintf("soak-%s-end", tag))
}

@(test)
soak_random :: proc(t: ^testing.T) {
	soak(1, 8000, "a")
	soak(2, 8000, "b")
}
