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

func TestResolveTokensPrefersShorterThenLowerPattern(t *testing.T) {
	// content: identifier "greet" (bytes 0..5) captured as both function (pattern 0)
	// and variable (pattern 2). variable maps to "" (skipped), function wins.
	content := "greet"
	idx := newLineColumnIndex(content)
	caps := []rawCapture{
		{start: 0, end: 5, pattern: 2, typ: ""},         // variable -> skipped upstream; pass typ "" to ensure it's ignored
		{start: 0, end: 5, pattern: 0, typ: "function"}, // function
	}
	tokens := resolveTokens(content, caps, idx)
	if len(tokens) != 1 {
		t.Fatalf("want 1 token, got %d: %+v", len(tokens), tokens)
	}
	tok := tokens[0]
	if tok.Type != "function" || tok.StartColumn != 1 || tok.EndColumn != 6 {
		t.Fatalf("unexpected token: %+v", tok)
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
