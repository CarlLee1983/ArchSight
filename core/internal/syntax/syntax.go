package syntax

import (
	"path/filepath"
	"strings"
	"unicode"
)

type Token struct {
	StartLine   int    `json:"startLine"`
	StartColumn int    `json:"startColumn"`
	EndLine     int    `json:"endLine"`
	EndColumn   int    `json:"endColumn"`
	Type        string `json:"type"`
}

type Result struct {
	Language string  `json:"language"`
	Tokens   []Token `json:"tokens"`
}

func Highlight(path, content string) Result {
	language := DetectLanguage(path)
	if language == "" {
		return Result{Tokens: []Token{}}
	}
	if language == "go" {
		return Result{Language: language, Tokens: highlightGo(content)}
	}
	return Result{
		Language: language,
		Tokens:   keywordTokens(language, content),
	}
}

func DetectLanguage(path string) string {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".go":
		return "go"
	case ".swift":
		return "swift"
	case ".ts", ".tsx":
		return "typescript"
	case ".md", ".markdown":
		return "markdown"
	default:
		return ""
	}
}

func keywordTokens(language, content string) []Token {
	keywords := keywordsFor(language)
	if len(keywords) == 0 {
		return []Token{}
	}

	var tokens []Token
	line := 1
	column := 1
	for i := 0; i < len(content); {
		r := rune(content[i])
		if r == '\n' {
			line++
			column = 1
			i++
			continue
		}
		if !isIdentStart(r) {
			column++
			i++
			continue
		}

		startLine := line
		startColumn := column
		start := i
		for i < len(content) && isIdentPart(rune(content[i])) {
			i++
			column++
		}
		word := content[start:i]
		if keywords[word] {
			tokens = append(tokens, Token{
				StartLine:   startLine,
				StartColumn: startColumn,
				EndLine:     line,
				EndColumn:   column,
				Type:        "keyword",
			})
		}
	}
	return tokens
}

func keywordsFor(language string) map[string]bool {
	switch language {
	case "go":
		return map[string]bool{
			"break": true, "case": true, "chan": true, "const": true, "continue": true,
			"default": true, "defer": true, "else": true, "fallthrough": true, "for": true,
			"func": true, "go": true, "goto": true, "if": true, "import": true,
			"interface": true, "map": true, "package": true, "range": true, "return": true,
			"select": true, "struct": true, "switch": true, "type": true, "var": true,
		}
	case "swift":
		return map[string]bool{
			"class": true, "deinit": true, "enum": true, "extension": true, "func": true,
			"import": true, "init": true, "let": true, "protocol": true, "struct": true,
			"subscript": true, "typealias": true, "var": true,
		}
	case "typescript":
		return map[string]bool{
			"async": true, "await": true, "class": true, "const": true, "export": true,
			"from": true, "function": true, "import": true, "interface": true, "let": true,
			"return": true, "type": true, "var": true,
		}
	default:
		return nil
	}
}

func isIdentStart(r rune) bool {
	return r == '_' || unicode.IsLetter(r)
}

func isIdentPart(r rune) bool {
	return isIdentStart(r) || unicode.IsDigit(r)
}
