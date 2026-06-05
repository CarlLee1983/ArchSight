package syntax

import (
	"strings"
	"testing"
)

const goSample = `package main

import "fmt"

// greet returns a greeting.
func greet(name string) string {
	return "hello, " + name
}

func main() {
	fmt.Println(greet("world"))
}
`

func tokensByType(tokens []Token) map[string]int {
	m := map[string]int{}
	for _, t := range tokens {
		m[t.Type]++
	}
	return m
}

func TestHighlightGoProducesRichTokens(t *testing.T) {
	tokens := highlightGo(goSample)
	if len(tokens) == 0 {
		t.Fatal("expected tokens for Go source")
	}
	counts := tokensByType(tokens)
	for _, typ := range []string{"keyword", "string", "comment", "function"} {
		if counts[typ] == 0 {
			t.Errorf("expected at least one %q token; got counts %+v", typ, counts)
		}
	}
	// Skipped capture types must never be emitted.
	for _, tok := range tokens {
		if tok.Type == "" || tok.Type == "variable" || tok.Type == "property" {
			t.Errorf("unexpected token type %q emitted", tok.Type)
		}
	}
}

func TestHighlightGoCommentPosition(t *testing.T) {
	// The comment is on line 5, starting at column 1.
	tokens := highlightGo(goSample)
	var found bool
	for _, tok := range tokens {
		if tok.Type == "comment" {
			found = true
			if tok.StartLine != 5 || tok.StartColumn != 1 {
				t.Fatalf("comment token at (%d,%d), want (5,1)", tok.StartLine, tok.StartColumn)
			}
		}
	}
	if !found {
		t.Fatal("no comment token found")
	}
}

func TestHighlightGoEmptyAndOversize(t *testing.T) {
	if got := highlightGo(""); len(got) != 0 {
		t.Fatalf("empty content should yield no tokens, got %d", len(got))
	}
	huge := "package main\n" + strings.Repeat("var x = 1\n", maxHighlightBytes/10)
	if len(huge) <= maxHighlightBytes {
		t.Fatalf("test fixture not large enough: %d", len(huge))
	}
	if got := highlightGo(huge); len(got) != 0 {
		t.Fatalf("oversize content should yield no tokens, got %d", len(got))
	}
}

func TestHighlightGoReuseDoesNotTrap(t *testing.T) {
	// Regression: a reused single instance traps (wasm unreachable) after ~270
	// parses. Per-call instances must survive well past that.
	src := "package main\n" + strings.Repeat("func f(x int) int { return x } // c\n", 80)
	for i := 0; i < 400; i++ {
		if len(highlightGo(src)) == 0 {
			t.Fatalf("highlight returned no tokens at iteration %d", i)
		}
	}
}
