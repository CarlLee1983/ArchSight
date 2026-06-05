package syntax

import "testing"

func TestHighlightRoutesGoToTreeSitter(t *testing.T) {
	res := Highlight("cmd/main.go", goSample)
	if res.Language != "go" {
		t.Fatalf("language = %q, want go", res.Language)
	}
	if tokensByType(res.Tokens)["function"] == 0 {
		t.Fatalf("expected tree-sitter function tokens, got %+v", res.Tokens)
	}
}

func TestHighlightKeepsKeywordFallbackForSwift(t *testing.T) {
	res := Highlight("App.swift", "import SwiftUI\nclass A {}\n")
	if res.Language != "swift" {
		t.Fatalf("language = %q, want swift", res.Language)
	}
	if len(res.Tokens) == 0 {
		t.Fatal("expected keyword tokens for swift")
	}
	for _, tok := range res.Tokens {
		if tok.Type != "keyword" {
			t.Fatalf("swift fallback should emit only keyword tokens, got %q", tok.Type)
		}
	}
}

func TestHighlightPlainTextForUnknown(t *testing.T) {
	res := Highlight("notes.txt", "hello world\n")
	if res.Language != "" || len(res.Tokens) != 0 {
		t.Fatalf("unknown extension should be plain text, got %+v", res)
	}
}
