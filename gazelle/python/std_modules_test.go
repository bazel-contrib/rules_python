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
	"testing"
	"testing/fstest"

	"github.com/stretchr/testify/assert"
)

func TestIsStdModule(t *testing.T) {
	assert.True(t, isStdModule(Module{Name: "unittest"}))
	assert.True(t, isStdModule(Module{Name: "os.path"}))
	assert.False(t, isStdModule(Module{Name: "foo"}))
}

func TestLoadStdModules(t *testing.T) {
	t.Run("prefers selected.txt when present", func(t *testing.T) {
		fsys := fstest.MapFS{
			"stdlib_list/default.txt":  &fstest.MapFile{Data: []byte("default_only\n")},
			"stdlib_list/selected.txt": &fstest.MapFile{Data: []byte("selected_only\n")},
		}
		modules, err := loadStdModules(fsys)
		if assert.NoError(t, err) {
			assert.Contains(t, modules, "selected_only")
			assert.NotContains(t, modules, "default_only")
		}
	})

	t.Run("falls back to default.txt when selected.txt is absent", func(t *testing.T) {
		fsys := fstest.MapFS{
			"stdlib_list/default.txt": &fstest.MapFile{Data: []byte("default_only\n")},
		}
		modules, err := loadStdModules(fsys)
		if assert.NoError(t, err) {
			assert.Contains(t, modules, "default_only")
		}
	})
}
