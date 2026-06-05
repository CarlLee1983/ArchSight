package syntax

import "sort"

// canonicalType maps a tree-sitter highlight capture name to ArchSight's stable
// token-type vocabulary. It returns "" for captures we do not render (including
// @variable/@property, which would only repaint the default text color).
func canonicalType(capture string) string {
	switch capture {
	case "keyword":
		return "keyword"
	case "string", "escape":
		return "string"
	case "comment":
		return "comment"
	case "number":
		return "number"
	case "constant", "constant.builtin":
		return "constant"
	case "function", "function.builtin", "function.method":
		return "function"
	case "type", "type.builtin":
		return "type"
	case "operator":
		return "operator"
	default:
		return ""
	}
}

// rawCapture is a single highlight capture in UTF-8 byte coordinates.
type rawCapture struct {
	start, end int    // byte offsets [start, end)
	pattern    int    // query pattern index; lower = higher priority
	typ        string // canonical token type ("" = ignore)
}

// resolveTokens paints non-overlapping highlight spans (most specific/shortest
// capture wins, ties broken by lower pattern index, then earlier start, then
// type name) and coalesces consecutive same-type bytes into Tokens with 1-based
// line/column.
func resolveTokens(content string, caps []rawCapture, idx *lineColumnIndex) []Token {
	n := len(content)
	owner := make([]int16, n)
	for i := range owner {
		owner[i] = -1
	}
	var types []string
	typeID := map[string]int16{}
	idFor := func(t string) int16 {
		if id, ok := typeID[t]; ok {
			return id
		}
		id := int16(len(types))
		types = append(types, t)
		typeID[t] = id
		return id
	}

	sorted := make([]rawCapture, 0, len(caps))
	for _, c := range caps {
		if c.typ == "" || c.start < 0 || c.end > n || c.start >= c.end {
			continue
		}
		sorted = append(sorted, c)
	}
	sort.SliceStable(sorted, func(a, b int) bool {
		la, lb := sorted[a].end-sorted[a].start, sorted[b].end-sorted[b].start
		if la != lb {
			return la < lb
		}
		if sorted[a].pattern != sorted[b].pattern {
			return sorted[a].pattern < sorted[b].pattern
		}
		if sorted[a].start != sorted[b].start {
			return sorted[a].start < sorted[b].start
		}
		return sorted[a].typ < sorted[b].typ
	})
	for _, c := range sorted {
		id := idFor(c.typ)
		for i := c.start; i < c.end; i++ {
			if owner[i] == -1 {
				owner[i] = id
			}
		}
	}

	var tokens []Token
	i := 0
	for i < n {
		if owner[i] == -1 {
			i++
			continue
		}
		j := i + 1
		for j < n && owner[j] == owner[i] {
			j++
		}
		sl, sc := idx.at(i)
		el, ec := idx.at(j)
		tokens = append(tokens, Token{
			StartLine:   sl,
			StartColumn: sc,
			EndLine:     el,
			EndColumn:   ec,
			Type:        types[owner[i]],
		})
		i = j
	}
	if tokens == nil {
		return []Token{}
	}
	return tokens
}
