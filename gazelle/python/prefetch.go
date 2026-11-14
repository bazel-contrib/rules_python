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
	"flag"
	"path"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/bazelbuild/bazel-gazelle/walk"
)

// GenerateRules parses Python files one package at a time, which keeps most
// CPUs idle. The prefetcher parses the files of the directories being updated
// on all CPUs, ahead of the walk, and GenerateRules picks up the results.
// It only changes when a file is parsed, not what is generated.
type prefetcher struct {
	repoRoot  string
	dirs      map[string]bool // directories being updated, relative to the repo root
	recursive bool
	sem       chan struct{} // limits concurrent parses

	listDir func(rel string) (walk.DirInfo, error) // walk.GetDirInfo, except in tests

	mu      sync.Mutex
	results map[prefetchKey]*prefetchResult
}

type prefetchKey struct{ rel, filename string }

type prefetchResult struct {
	key  prefetchKey
	done chan struct{}
	out  *ParserOutput
	err  error
}

var activePrefetcher atomic.Pointer[prefetcher]

// newPrefetcher returns nil, which turns prefetching off, unless this is an
// update of directories inside the repo.
func newPrefetcher(fs *flag.FlagSet, repoRoot, workDir string) *prefetcher {
	if fs.Lookup("mode") == nil {
		return nil
	}
	recursive := true
	if f := fs.Lookup("r"); f != nil {
		recursive = f.Value.String() == "true"
	}
	args := fs.Args()
	if len(args) == 0 {
		args = []string{"."}
	}
	root, err := filepath.EvalSymlinks(repoRoot)
	if err != nil {
		return nil
	}
	dirs := make(map[string]bool, len(args))
	for _, dir := range args {
		if !filepath.IsAbs(dir) {
			dir = filepath.Join(workDir, dir)
		}
		dir, err := filepath.EvalSymlinks(dir)
		if err != nil {
			return nil
		}
		rel, err := filepath.Rel(root, dir)
		if err != nil || rel == ".." || strings.HasPrefix(rel, "../") {
			return nil
		}
		if rel = filepath.ToSlash(rel); rel == "." {
			rel = ""
		}
		dirs[rel] = true
	}
	return &prefetcher{
		repoRoot:  repoRoot,
		dirs:      dirs,
		recursive: recursive,
		sem:       make(chan struct{}, runtime.GOMAXPROCS(0)),
		listDir:   walk.GetDirInfo,
		results:   make(map[prefetchKey]*prefetchResult),
	}
}

// enqueueDir is called by Configure for every directory. For a directory being
// updated, it starts parsing the Python files in it, in walk order.
func (pf *prefetcher) enqueueDir(rel string) {
	if pf == nil || !pf.dirs[rel] {
		return
	}
	delete(pf.dirs, rel)

	keys := pf.pythonFiles(rel)
	var jobs []*prefetchResult
	pf.mu.Lock()
	for _, k := range keys {
		if _, ok := pf.results[k]; !ok {
			r := &prefetchResult{key: k, done: make(chan struct{})}
			pf.results[k] = r
			jobs = append(jobs, r)
		}
	}
	pf.mu.Unlock()

	go func() {
		for _, r := range jobs {
			pf.sem <- struct{}{}
			go func(r *prefetchResult) {
				defer func() { <-pf.sem }()
				out, err := NewFileParser().ParseFile(context.Background(), pf.repoRoot, r.key.rel, r.key.filename)
				if out != nil {
					o := *out // out points into the parser, which also holds the file contents
					out = &o
				}
				r.out, r.err = out, err
				close(r.done)
			}(r)
		}
	}()
}

// pythonFiles lists the Python files in rel, and in its subdirectories if
// recursive, in the order GenerateRules sees them: subdirectories first.
func (pf *prefetcher) pythonFiles(rel string) []prefetchKey {
	var keys []prefetchKey
	var visit func(rel string)
	visit = func(rel string) {
		info, err := pf.listDir(rel) // Gazelle's cached listing, excludes applied
		if err != nil {
			return
		}
		if pf.recursive {
			for _, sub := range info.Subdirs {
				visit(path.Join(rel, sub))
			}
		}
		for _, f := range info.RegularFiles {
			if filepath.Ext(f) == ".py" {
				keys = append(keys, prefetchKey{rel, f})
			}
		}
	}
	visit(rel)
	return keys
}

// parseFile returns the prefetched result for a file, or else parses it.
func parseFile(ctx context.Context, repoRoot, rel, filename string) (*ParserOutput, error) {
	if pf := activePrefetcher.Load(); pf != nil {
		k := prefetchKey{rel, filename}
		pf.mu.Lock()
		r := pf.results[k]
		delete(pf.results, k)
		pf.mu.Unlock()
		if r != nil {
			<-r.done
			return r.out, r.err
		}
	}
	return NewFileParser().ParseFile(ctx, repoRoot, rel, filename)
}
