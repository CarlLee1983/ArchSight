package perf

import (
	"os"
	"reflect"
	"syscall"
	"testing"
)

func TestParseRSSKilobytes(t *testing.T) {
	cases := []struct {
		name    string
		in      string
		want    int
		wantErr bool
	}{
		{name: "padded", in: "  12345\n", want: 12345},
		{name: "plain", in: "42", want: 42},
		{name: "empty", in: "   \n", wantErr: true},
		{name: "non-numeric", in: "RSS\n", wantErr: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ParseRSSKilobytes(tc.in)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected error for %q", tc.in)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Fatalf("expected %d, got %d", tc.want, got)
			}
		})
	}
}

func TestParsePIDList(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want []int
	}{
		{name: "multiple", in: "101\n202\n303\n", want: []int{101, 202, 303}},
		{name: "blank-lines", in: "\n101\n\n", want: []int{101}},
		{name: "empty", in: "", want: nil},
		{name: "noise", in: "abc\n5\n", want: []int{5}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ParsePIDList(tc.in)
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("expected %v, got %v", tc.want, got)
			}
		})
	}
}

func TestIsAlive(t *testing.T) {
	if !IsAlive(os.Getpid()) {
		t.Fatal("expected current process to be alive")
	}
	if IsAlive(-1) {
		t.Fatal("expected negative pid to be not alive")
	}
	// PID 1 (launchd/init) exists but is owned by root; IsAlive treats EPERM as
	// alive, so this should be true on a normal system.
	if !IsAlive(1) {
		t.Fatal("expected pid 1 to be reported alive")
	}
}

func TestDescendantPIDsNoChildren(t *testing.T) {
	// A leaf process (the test binary itself usually has children from the test
	// runner, so assert the API succeeds rather than emptiness).
	if _, err := DescendantPIDs(os.Getpid()); err != nil {
		t.Fatalf("DescendantPIDs returned error: %v", err)
	}
}

func TestProcessGroupPIDsIncludesSelf(t *testing.T) {
	pgid, err := syscall.Getpgid(os.Getpid())
	if err != nil {
		t.Fatalf("Getpgid returned error: %v", err)
	}
	pids, err := ProcessGroupPIDs(pgid)
	if err != nil {
		t.Fatalf("ProcessGroupPIDs returned error: %v", err)
	}
	found := false
	for _, pid := range pids {
		if pid == os.Getpid() {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected current pid %d in its process group %v", os.Getpid(), pids)
	}
}
