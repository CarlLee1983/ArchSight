package search

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/cmg/archsight/core/internal/workspace"
)

type Options struct {
	Path string
}

type Request struct {
	Pattern string
	Roots   []workspace.Root
}

type Match struct {
	RootID   string  `json:"rootId"`
	RootPath string  `json:"rootPath"`
	Path     string  `json:"path"`
	Line     int     `json:"line"`
	Column   int     `json:"column"`
	Preview  string  `json:"preview"`
	Ranges   []Range `json:"ranges"`
}

type Range struct {
	Start int `json:"start"`
	End   int `json:"end"`
}

type Error struct {
	Code    string
	Message string
}

func (e *Error) Error() string {
	return e.Code + ": " + e.Message
}

type RipgrepSearcher struct {
	path string
}

type Searcher interface {
	Search(context.Context, Request, func(Match) error) error
}

func NewRipgrepSearcher(options Options) *RipgrepSearcher {
	path := options.Path
	if path == "" {
		path = "rg"
	}
	return &RipgrepSearcher{path: path}
}

func (s *RipgrepSearcher) Search(ctx context.Context, req Request, emit func(Match) error) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if req.Pattern == "" {
		return &Error{Code: "invalid_pattern", Message: "Search pattern is required"}
	}
	if len(req.Roots) == 0 {
		return &Error{Code: "invalid_request", Message: "At least one search root is required"}
	}

	cmd := s.command(ctx, req)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Start(); err != nil {
		return err
	}

	scanErr := parseJSONLines(stdout, req.Roots, emit)
	waitErr := cmd.Wait()
	if err := ctx.Err(); err != nil {
		return err
	}
	if scanErr != nil {
		return scanErr
	}
	if waitErr != nil {
		if exitErr, ok := waitErr.(*exec.ExitError); ok {
			switch exitErr.ExitCode() {
			case 1:
				return nil
			case 2:
				return &Error{Code: "invalid_pattern", Message: strings.TrimSpace(stderr.String())}
			}
		}
		return waitErr
	}
	return nil
}

func (s *RipgrepSearcher) command(ctx context.Context, req Request) *exec.Cmd {
	args := []string{
		"--json",
		"--line-number",
		"--column",
		"--color", "never",
		"--glob", "!.git/**",
		"--glob", "!**/.git/**",
		"--glob", "!node_modules/**",
		"--glob", "!**/node_modules/**",
		"--glob", "!build/**",
		"--glob", "!**/build/**",
		"--glob", "!.next/**",
		"--glob", "!**/.next/**",
		"--glob", "!DerivedData/**",
		"--glob", "!**/DerivedData/**",
		"--glob", "!vendor/**",
		"--glob", "!**/vendor/**",
		"--glob", "!.cache/**",
		"--glob", "!**/.cache/**",
		req.Pattern,
	}
	for _, root := range req.Roots {
		args = append(args, root.Path)
	}
	return exec.CommandContext(ctx, s.path, args...)
}

func parseJSONLines(stdout anyReader, roots []workspace.Root, emit func(Match) error) error {
	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		var event rgEvent
		if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
			return err
		}
		if event.Type != "match" {
			continue
		}
		match, err := convertMatch(event.Data, roots)
		if err != nil {
			return err
		}
		if err := emit(match); err != nil {
			return err
		}
	}
	return scanner.Err()
}

type anyReader interface {
	Read([]byte) (int, error)
}

type rgEvent struct {
	Type string  `json:"type"`
	Data rgMatch `json:"data"`
}

type rgMatch struct {
	Path struct {
		Text string `json:"text"`
	} `json:"path"`
	LineNumber int `json:"line_number"`
	Lines      struct {
		Text string `json:"text"`
	} `json:"lines"`
	Submatches []struct {
		Start int `json:"start"`
		End   int `json:"end"`
	} `json:"submatches"`
}

func convertMatch(data rgMatch, roots []workspace.Root) (Match, error) {
	root, rel, ok := resolveRoot(data.Path.Text, roots)
	if !ok {
		return Match{}, fmt.Errorf("search result did not belong to an opened root: %s", data.Path.Text)
	}
	ranges := make([]Range, 0, len(data.Submatches))
	column := 0
	for i, submatch := range data.Submatches {
		if i == 0 {
			column = submatch.Start + 1
		}
		ranges = append(ranges, Range{
			Start: submatch.Start,
			End:   submatch.End,
		})
	}
	return Match{
		RootID:   root.ID,
		RootPath: root.Path,
		Path:     filepath.ToSlash(rel),
		Line:     data.LineNumber,
		Column:   column,
		Preview:  strings.TrimRight(data.Lines.Text, "\r\n"),
		Ranges:   ranges,
	}, nil
}

func resolveRoot(path string, roots []workspace.Root) (workspace.Root, string, bool) {
	cleaned, err := filepath.Abs(path)
	if err != nil {
		cleaned = path
	}
	for _, root := range roots {
		rel, err := filepath.Rel(root.Path, cleaned)
		if err != nil || rel == "." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || rel == ".." {
			continue
		}
		return root, rel, true
	}
	return workspace.Root{}, "", false
}

func AsError(err error, target **Error) bool {
	return errors.As(err, target)
}
