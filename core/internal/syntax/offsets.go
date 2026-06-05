package syntax

// lineColumnIndex converts a UTF-8 byte offset into a 1-based line and a 1-based
// column counted in UTF-16 code units, matching the position contract the macOS
// client uses (see apps/macos TextPosition).
type lineColumnIndex struct {
	content    string
	lineStarts []int // byte offset of each line start; line 1 at index 0
}

func newLineColumnIndex(content string) *lineColumnIndex {
	starts := []int{0}
	for i := 0; i < len(content); i++ {
		if content[i] == '\n' {
			starts = append(starts, i+1)
		}
	}
	return &lineColumnIndex{content: content, lineStarts: starts}
}

// at returns the 1-based (line, column) for a byte offset. Offsets are clamped
// to [0, len(content)]. Callers pass node boundary offsets, which fall on valid
// UTF-8 rune boundaries.
func (x *lineColumnIndex) at(byteOffset int) (int, int) {
	if byteOffset < 0 {
		byteOffset = 0
	}
	if byteOffset > len(x.content) {
		byteOffset = len(x.content)
	}
	lo, hi := 0, len(x.lineStarts)-1
	for lo < hi {
		mid := (lo + hi + 1) / 2
		if x.lineStarts[mid] <= byteOffset {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	line := lo + 1
	col := 1 + utf16Len(x.content[x.lineStarts[lo]:byteOffset])
	return line, col
}

// utf16Len counts the UTF-16 code units in s (surrogate pairs count as 2).
func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		if r > 0xFFFF {
			n += 2
		} else {
			n++
		}
	}
	return n
}
