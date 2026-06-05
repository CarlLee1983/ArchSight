package syntax

import "testing"

func TestLineColumnIndexAscii(t *testing.T) {
	content := "package main\nfunc f() {}\n"
	idx := newLineColumnIndex(content)

	// byte 0 -> line 1, col 1
	if l, c := idx.at(0); l != 1 || c != 1 {
		t.Fatalf("at(0) = (%d,%d), want (1,1)", l, c)
	}
	// "func" starts at byte 13 (after "package main\n") -> line 2, col 1
	if l, c := idx.at(13); l != 2 || c != 1 {
		t.Fatalf("at(13) = (%d,%d), want (2,1)", l, c)
	}
	// byte 18 is 'f' of f() -> line 2, col 6
	if l, c := idx.at(18); l != 2 || c != 6 {
		t.Fatalf("at(18) = (%d,%d), want (2,6)", l, c)
	}
}

func TestLineColumnIndexUTF16Columns(t *testing.T) {
	// "é" is 2 UTF-8 bytes but 1 UTF-16 unit; "😀" is 4 UTF-8 bytes and 2 UTF-16 units.
	content := "a\"é\"😀x"
	idx := newLineColumnIndex(content)
	// bytes: a(0) "(1) é(2,3) "(4) 😀(5,6,7,8) x(9)
	// UTF-16 units before byte 9: a, ", é, ", 😀(2 units) = 6 -> column 7.
	if l, c := idx.at(9); l != 1 || c != 7 {
		t.Fatalf("at(9) = (%d,%d), want (1,7)", l, c)
	}
}

func TestLineColumnIndexEndOfFileNoTrailingNewline(t *testing.T) {
	content := "abc\ndef" // no trailing newline; len == 7
	idx := newLineColumnIndex(content)
	if l, c := idx.at(len(content)); l != 2 || c != 4 {
		t.Fatalf("at(len) = (%d,%d), want (2,4)", l, c)
	}
}

func TestLineColumnIndexClamps(t *testing.T) {
	idx := newLineColumnIndex("abc")
	if l, c := idx.at(-5); l != 1 || c != 1 {
		t.Fatalf("at(-5) = (%d,%d), want (1,1)", l, c)
	}
	if l, c := idx.at(999); l != 1 || c != 4 {
		t.Fatalf("at(999) = (%d,%d), want (1,4)", l, c)
	}
}
