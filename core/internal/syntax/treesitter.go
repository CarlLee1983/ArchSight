package syntax

import (
	_ "embed"
	"fmt"

	sitter "github.com/malivvan/tree-sitter"
)

//go:embed queries/go/highlights.scm
var goHighlightQuery string

// maxHighlightBytes caps the file size we highlight; larger files render as
// plain text. This bounds per-call parse cost and Wasm memory.
const maxHighlightBytes = 1 << 20 // 1 MiB

// highlightGo returns Tree-sitter highlight tokens for Go source. Any failure
// (init, parse, query, or panic) degrades to an empty slice so highlighting
// never blocks file viewing or crashes the core.
func highlightGo(content string) []Token {
	if len(content) == 0 || len(content) > maxHighlightBytes {
		return []Token{}
	}
	tokens, err := tryHighlightGo(content)
	if err != nil || tokens == nil {
		return []Token{}
	}
	return tokens
}

// tryHighlightGo builds a fresh Tree-sitter instance, parses, runs the highlight
// query, and resolves tokens. A fresh instance per call is required: the pinned
// binding has no free/Close for trees/cursors/modules, so a reused instance
// leaks Wasm memory and traps after a few hundred parses. The compiled Wasm
// module is cached process-globally by the binding, so only the first call pays
// the compile cost.
func tryHighlightGo(content string) (_ []Token, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("tree-sitter highlight panicked: %v", r)
		}
	}()

	ts, err := sitter.New(nil, nil)
	if err != nil {
		return nil, err
	}
	lang, err := ts.Language("go")
	if err != nil {
		return nil, err
	}
	query, err := ts.NewQuery(goHighlightQuery, lang)
	if err != nil {
		return nil, err
	}
	parser, err := ts.NewParser()
	if err != nil {
		return nil, err
	}
	defer parser.Close()
	if err := parser.SetLanguage(lang); err != nil {
		return nil, err
	}
	tree, err := parser.ParseString(content)
	if err != nil {
		return nil, err
	}
	root, err := tree.RootNode()
	if err != nil {
		return nil, err
	}
	cursor, err := ts.NewQueryCursor()
	if err != nil {
		return nil, err
	}
	if err := cursor.Exec(query, root); err != nil {
		return nil, err
	}

	var caps []rawCapture
	for {
		match, ok, err := cursor.NextMatch()
		if err != nil {
			return nil, err
		}
		if !ok {
			break
		}
		for _, c := range match.Captures {
			name, err := query.CaptureNameForID(c.ID)
			if err != nil {
				return nil, err
			}
			typ := canonicalType(name)
			if typ == "" {
				continue
			}
			sb, err := c.Node.StartByte()
			if err != nil {
				return nil, err
			}
			eb, err := c.Node.EndByte()
			if err != nil {
				return nil, err
			}
			caps = append(caps, rawCapture{
				start:   int(sb),
				end:     int(eb),
				pattern: int(match.PatternIndex),
				typ:     typ,
			})
		}
	}
	return resolveTokens(content, caps, newLineColumnIndex(content)), nil
}
