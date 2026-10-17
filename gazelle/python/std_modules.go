// Copyright 2023 The Bazel Authors. All rights reserved.
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
	"bufio"
	"bytes"
	"embed"
	"io/fs"
)

var (
	//go:embed stdlib_list/*.txt
	stdlibFS   embed.FS
	stdModules map[string]struct{}
)

func init() {
	var err error
	stdModules, err = loadStdModules(stdlibFS)
	if err != nil {
		panic(err)
	}
}

func loadStdModules(fsys fs.ReadFileFS) (map[string]struct{}, error) {
	data, err := fsys.ReadFile("stdlib_list/selected.txt")
	if err != nil {
		data, err = fsys.ReadFile("stdlib_list/default.txt")
		if err != nil {
			return nil, err
		}
	}
	modules := make(map[string]struct{})
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		modules[scanner.Text()] = struct{}{}
	}
	return modules, scanner.Err()
}

func isStdModule(m Module) bool {
	_, ok := stdModules[m.Name]
	return ok
}
