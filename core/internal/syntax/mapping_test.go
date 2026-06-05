package syntax

import "testing"

func TestCanonicalType(t *testing.T) {
	cases := map[string]string{
		"keyword":          "keyword",
		"string":           "string",
		"escape":           "string",
		"comment":          "comment",
		"number":           "number",
		"constant.builtin": "constant",
		"function":         "function",
		"function.method":  "function",
		"function.builtin": "function",
		"type":             "type",
		"operator":         "operator",
		"variable":         "", // not emitted (renders as default text color)
		"property":         "", // not emitted
		"unknownthing":     "",
	}
	for name, want := range cases {
		if got := canonicalType(name); got != want {
			t.Errorf("canonicalType(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestResolveTokensPrefersLowerPatternOnEqualSpan(t *testing.T) {
	// Same byte span [0,5), equal length: function (pattern 0) vs type (pattern 1).
	// Lower pattern index wins.
	content := "greet"
	idx := newLineColumnIndex(content)
	caps := []rawCapture{
		{start: 0, end: 5, pattern: 1, typ: "type"},
		{start: 0, end: 5, pattern: 0, typ: "function"},
	}
	tokens := resolveTokens(content, caps, idx)
	if len(tokens) != 1 || tokens[0].Type != "function" || tokens[0].StartColumn != 1 || tokens[0].EndColumn != 6 {
		t.Fatalf("expected one function token cols 1..6, got %+v", tokens)
	}
}

func TestResolveTokensMultilineToken(t *testing.T) {
	content := "a\nb" // a raw-string-like span across the newline, bytes [0,3)
	idx := newLineColumnIndex(content)
	caps := []rawCapture{{start: 0, end: 3, pattern: 0, typ: "string"}}
	tokens := resolveTokens(content, caps, idx)
	if len(tokens) != 1 {
		t.Fatalf("want 1 token, got %+v", tokens)
	}
	if tokens[0].StartLine != 1 || tokens[0].EndLine != 2 {
		t.Fatalf("want token spanning lines 1->2, got %+v", tokens[0])
	}
}

func TestResolveTokensCoalescesStringWithEscape(t *testing.T) {
	// "a\nb" as a Go string literal: outer string (bytes 0..6) with an escape
	// (bytes 2..4) inside. Both map to "string" -> one contiguous token.
	content := `"a\nb"`
	idx := newLineColumnIndex(content)
	caps := []rawCapture{
		{start: 0, end: 6, pattern: 5, typ: "string"},
		{start: 2, end: 4, pattern: 6, typ: "string"},
	}
	tokens := resolveTokens(content, caps, idx)
	if len(tokens) != 1 || tokens[0].Type != "string" || tokens[0].StartColumn != 1 || tokens[0].EndColumn != 7 {
		t.Fatalf("want one string token spanning the literal, got %+v", tokens)
	}
}

func TestResolveTokensSkipsEmptyAndOutOfRange(t *testing.T) {
	content := "abc"
	idx := newLineColumnIndex(content)
	caps := []rawCapture{
		{start: 0, end: 3, pattern: 0, typ: ""},   // skipped: empty type
		{start: 1, end: 99, pattern: 0, typ: "x"}, // skipped: out of range
	}
	if tokens := resolveTokens(content, caps, idx); len(tokens) != 0 {
		t.Fatalf("want 0 tokens, got %+v", tokens)
	}
}
