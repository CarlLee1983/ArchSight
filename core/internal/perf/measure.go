// Package perf provides process-level measurement helpers used by the Phase 9
// performance and reliability gate: resident memory, process descendants, and
// liveness checks against a running core process.
//
// These helpers shell out to the BSD/macOS `ps` and `pgrep` tools and assume
// macOS semantics (notably that `ps -o rss=` reports kilobytes). ArchSight is a
// macOS-only product, so this is intentional rather than portable.
package perf

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
)

// ParseRSSKilobytes parses the output of `ps -o rss=` (resident set size in
// kilobytes). macOS pads the value with leading spaces and a trailing newline.
func ParseRSSKilobytes(out string) (int, error) {
	trimmed := strings.TrimSpace(out)
	if trimmed == "" {
		return 0, fmt.Errorf("empty rss output")
	}
	value, err := strconv.Atoi(trimmed)
	if err != nil {
		return 0, fmt.Errorf("parse rss %q: %w", trimmed, err)
	}
	return value, nil
}

// ParsePIDList parses newline-separated PIDs as emitted by `pgrep -P`. Blank
// lines and non-numeric noise are skipped so an empty result is a clean nil.
func ParsePIDList(out string) []int {
	var pids []int
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		pid, err := strconv.Atoi(line)
		if err != nil {
			continue
		}
		pids = append(pids, pid)
	}
	return pids
}

// ProcessRSSKilobytes returns the resident set size of pid in kilobytes.
func ProcessRSSKilobytes(pid int) (int, error) {
	out, err := exec.Command("ps", "-o", "rss=", "-p", strconv.Itoa(pid)).Output()
	if err != nil {
		return 0, fmt.Errorf("ps rss for pid %d: %w", pid, err)
	}
	return ParseRSSKilobytes(string(out))
}

// childPIDs returns the direct children of pid using pgrep. An exit status of 1
// from pgrep means "no matches", which is reported as an empty slice.
func childPIDs(pid int) ([]int, error) {
	out, err := exec.Command("pgrep", "-P", strconv.Itoa(pid)).Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			return nil, nil
		}
		return nil, fmt.Errorf("pgrep -P %d: %w", pid, err)
	}
	return ParsePIDList(string(out)), nil
}

// ProcessGroupPIDs returns every live process in the given process group. After
// the group leader exits, any survivor is an orphan that the leader failed to
// clean up. Unlike walking descendants by parent pid, group membership is stable
// across reparenting (to launchd) and immune to pid-reuse races, because a
// recycled pid will not belong to this group.
//
// It uses `ps -g` rather than `pgrep -g`, because macOS `pgrep -g` does not
// match by process group reliably (it reports no matches for populated groups).
func ProcessGroupPIDs(pgid int) ([]int, error) {
	out, err := exec.Command("ps", "-g", strconv.Itoa(pgid), "-o", "pid=").Output()
	if err != nil {
		// ps exits non-zero for an empty (or unknown) group; treat that as "no
		// members" rather than an error so an empty group is a clean result.
		if _, ok := err.(*exec.ExitError); ok {
			return ParsePIDList(string(out)), nil
		}
		return nil, fmt.Errorf("ps -g %d: %w", pgid, err)
	}
	return ParsePIDList(string(out)), nil
}

// DescendantPIDs returns every transitive child process of pid.
func DescendantPIDs(pid int) ([]int, error) {
	var all []int
	queue := []int{pid}
	for len(queue) > 0 {
		current := queue[0]
		queue = queue[1:]
		children, err := childPIDs(current)
		if err != nil {
			return nil, err
		}
		all = append(all, children...)
		queue = append(queue, children...)
	}
	return all, nil
}

// IsAlive reports whether a process with the given pid currently exists. It uses
// signal 0, which performs permission and existence checks without delivering a
// signal.
func IsAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || err == syscall.EPERM
}
