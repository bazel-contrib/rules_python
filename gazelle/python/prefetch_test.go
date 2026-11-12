// Copyright 2026 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package python

import (
	"context"
	"errors"
	"flag"
	"os"
	"path/filepath"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/walk"
	"github.com/stretchr/testify/assert"
)

func TestNewPrefetcher(t *testing.T) {
	t.Parallel()
	repo := t.TempDir()
	if err := os.MkdirAll(filepath.Join(repo, "a", "b"), 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(repo, link); err != nil {
		t.Fatal(err)
	}
	outside := t.TempDir()

	tests := []struct {
		name          string
		flags         *flag.FlagSet
		repoRoot      string
		workDir       string
		wantDirs      map[string]bool // nil: no prefetcher
		wantRecursive bool
	}{
		{
			name:     "not update or fix",
			flags:    flag.NewFlagSet("help", flag.ContinueOnError),
			repoRoot: repo,
			workDir:  repo,
		},
		{
			name:          "no args updates the work dir",
			flags:         updateFlags(t),
			repoRoot:      repo,
			workDir:       filepath.Join(repo, "a"),
			wantDirs:      map[string]bool{"a": true},
			wantRecursive: true,
		},
		{
			name:          "relative args are relative to the work dir",
			flags:         updateFlags(t, "b", "."),
			repoRoot:      repo,
			workDir:       filepath.Join(repo, "a"),
			wantDirs:      map[string]bool{"a/b": true, "a": true},
			wantRecursive: true,
		},
		{
			name:          "absolute args",
			flags:         updateFlags(t, filepath.Join(repo, "a", "b"), repo),
			repoRoot:      repo,
			workDir:       repo,
			wantDirs:      map[string]bool{"a/b": true, "": true},
			wantRecursive: true,
		},
		{
			name:     "not recursive",
			flags:    updateFlags(t, "-r=false"),
			repoRoot: repo,
			workDir:  repo,
			wantDirs: map[string]bool{"": true},
		},
		{
			name:          "repo root through a symlink",
			flags:         updateFlags(t, "b"),
			repoRoot:      link,
			workDir:       filepath.Join(repo, "a"),
			wantDirs:      map[string]bool{"a/b": true},
			wantRecursive: true,
		},
		{
			name:     "directory outside the repo",
			flags:    updateFlags(t, outside),
			repoRoot: repo,
			workDir:  repo,
		},
		{
			name:     "missing directory",
			flags:    updateFlags(t, "missing"),
			repoRoot: repo,
			workDir:  repo,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			pf := newPrefetcher(tc.flags, tc.repoRoot, tc.workDir)
			if tc.wantDirs == nil {
				assert.Nil(t, pf)
				return
			}
			if assert.NotNil(t, pf) {
				assert.Equal(t, tc.wantDirs, pf.dirs)
				assert.Equal(t, tc.wantRecursive, pf.recursive)
			}
		})
	}
}

func TestPrefetcherPythonFiles(t *testing.T) {
	t.Parallel()
	listDir := fakeListDir(map[string]walk.DirInfo{
		"":    {Subdirs: []string{"a", "c"}, RegularFiles: []string{"BUILD.bazel", "root.py"}},
		"a":   {Subdirs: []string{"b", "unreadable"}, RegularFiles: []string{"README.md", "a1.py", "a2.py"}},
		"a/b": {RegularFiles: []string{"b.py"}},
		"c":   {RegularFiles: []string{"c.py", "c.pyi"}},
	})

	tests := []struct {
		name      string
		rel       string
		recursive bool
		want      []prefetchKey
	}{
		{
			name:      "recursive, subdirectories first",
			rel:       "",
			recursive: true,
			want:      []prefetchKey{{"a/b", "b.py"}, {"a", "a1.py"}, {"a", "a2.py"}, {"c", "c.py"}, {"", "root.py"}},
		},
		{
			name:      "subdirectory",
			rel:       "a",
			recursive: true,
			want:      []prefetchKey{{"a/b", "b.py"}, {"a", "a1.py"}, {"a", "a2.py"}},
		},
		{
			name: "not recursive",
			rel:  "a",
			want: []prefetchKey{{"a", "a1.py"}, {"a", "a2.py"}},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			pf := &prefetcher{recursive: tc.recursive, listDir: listDir}
			assert.Equal(t, tc.want, pf.pythonFiles(tc.rel))
		})
	}
}

// The tests below don't call t.Parallel because they set activePrefetcher.

func TestParseFileUsesPrefetchedResults(t *testing.T) {
	repo := t.TempDir()
	writeFiles(t, repo, map[string]string{
		"a/a.py":   "import os\nimport foo.bar\n",
		"a/b/b.py": "from a import a\n\nif __name__ == \"__main__\":\n    a.main()\n",
		"c/c.py":   "import yaml\n",
	})
	pf := &prefetcher{
		repoRoot:  repo,
		dirs:      map[string]bool{"a": true}, // c isn't being updated
		recursive: true,
		sem:       make(chan struct{}, 2),
		listDir: fakeListDir(map[string]walk.DirInfo{
			"":    {Subdirs: []string{"a", "c"}},
			"a":   {Subdirs: []string{"b"}, RegularFiles: []string{"a.py"}},
			"a/b": {RegularFiles: []string{"b.py"}},
			"c":   {RegularFiles: []string{"c.py"}},
		}),
		results: make(map[prefetchKey]*prefetchResult),
	}
	activePrefetcher.Store(pf)
	t.Cleanup(func() { activePrefetcher.Store(nil) })

	// Configure calls enqueueDir for every directory, parents first.
	for _, rel := range []string{"", "a", "a/b", "c", "a"} {
		pf.enqueueDir(rel)
	}
	assert.Empty(t, pf.dirs)
	var prefetched []prefetchKey
	pf.mu.Lock()
	for k := range pf.results {
		prefetched = append(prefetched, k)
	}
	pf.mu.Unlock()
	assert.ElementsMatch(t, []prefetchKey{{"a/b", "b.py"}, {"a", "a.py"}}, prefetched)

	// GenerateRules then parses the files, subdirectories first.
	ctx := context.Background()
	for _, k := range []prefetchKey{{"a/b", "b.py"}, {"a", "a.py"}, {"c", "c.py"}} {
		want, err := NewFileParser().ParseFile(ctx, repo, k.rel, k.filename)
		if !assert.NoError(t, err) {
			continue
		}
		got, err := parseFile(ctx, repo, k.rel, k.filename)
		if assert.NoError(t, err) {
			assert.Equal(t, want, got, k)
		}
		// A prefetched result is handed out once; after that the file is parsed
		// again.
		again, err := parseFile(ctx, repo, k.rel, k.filename)
		if assert.NoError(t, err) {
			assert.Equal(t, want, again, k)
		}
	}
	assert.Empty(t, pf.results)
}

func TestParseFileReturnsPrefetchError(t *testing.T) {
	r := &prefetchResult{done: make(chan struct{}), err: errors.New("prefetch failed")}
	close(r.done)
	activePrefetcher.Store(&prefetcher{results: map[prefetchKey]*prefetchResult{{"a", "a.py"}: r}})
	t.Cleanup(func() { activePrefetcher.Store(nil) })

	_, err := parseFile(context.Background(), t.TempDir(), "a", "a.py")
	assert.EqualError(t, err, "prefetch failed")
}

func TestParseFileWithoutPrefetcher(t *testing.T) {
	repo := t.TempDir()
	writeFiles(t, repo, map[string]string{"a/a.py": "import os\n"})
	activePrefetcher.Store(nil)

	var pf *prefetcher
	pf.enqueueDir("a") // a nil prefetcher does nothing

	ctx := context.Background()
	want, err := NewFileParser().ParseFile(ctx, repo, "a", "a.py")
	assert.NoError(t, err)
	got, err := parseFile(ctx, repo, "a", "a.py")
	assert.NoError(t, err)
	assert.Equal(t, want, got)
}

// updateFlags returns the flags of gazelle's update command that
// newPrefetcher reads, parsed from args.
func updateFlags(t *testing.T, args ...string) *flag.FlagSet {
	t.Helper()
	fs := flag.NewFlagSet("update", flag.ContinueOnError)
	fs.String("mode", "fix", "")
	fs.Bool("r", true, "")
	if err := fs.Parse(args); err != nil {
		t.Fatal(err)
	}
	return fs
}

// fakeListDir returns a replacement for walk.GetDirInfo that serves the
// listings in dirs and fails for other directories.
func fakeListDir(dirs map[string]walk.DirInfo) func(string) (walk.DirInfo, error) {
	return func(rel string) (walk.DirInfo, error) {
		if info, ok := dirs[rel]; ok {
			return info, nil
		}
		return walk.DirInfo{}, os.ErrNotExist
	}
}

// writeFiles creates files with the given contents, by slash-separated path
// relative to dir.
func writeFiles(t *testing.T, dir string, files map[string]string) {
	t.Helper()
	for name, content := range files {
		path := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}
