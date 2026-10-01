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
	"context"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParseImportStatements(t *testing.T) {
	t.Parallel()
	units := []struct {
		name     string
		code     string
		filepath string
		result   []Module
	}{
		{
			name:     "not has import",
			code:     "a = 1\nb = 2",
			filepath: "",
			result:   nil,
		},
		{
			name:     "has import",
			code:     "import unittest\nimport os.path\nfrom foo.bar import abc.xyz",
			filepath: "abc.py",
			result: []Module{
				{
					Name:       "unittest",
					LineNumber: 1,
					Filepath:   "abc.py",
					From:       "",
				},
				{
					Name:       "os.path",
					LineNumber: 2,
					Filepath:   "abc.py",
					From:       "",
				},
				{
					Name:       "foo.bar.abc.xyz",
					LineNumber: 3,
					Filepath:   "abc.py",
					From:       "foo.bar",
				},
			},
		},
		{
			name: "has import in def",
			code: `def foo():
	import unittest
`,
			filepath: "abc.py",
			result: []Module{
				{
					Name:       "unittest",
					LineNumber: 2,
					Filepath:   "abc.py",
					From:       "",
				},
			},
		},
		{
			name:     "invalid syntax",
			code:     "import os\nimport",
			filepath: "abc.py",
			result: []Module{
				{
					Name:       "os",
					LineNumber: 1,
					Filepath:   "abc.py",
					From:       "",
				},
			},
		},
		{
			name:     "import as",
			code:     "import os as b\nfrom foo import bar as c# 123",
			filepath: "abc.py",
			result: []Module{
				{
					Name:       "os",
					LineNumber: 1,
					Filepath:   "abc.py",
					From:       "",
				},
				{
					Name:       "foo.bar",
					LineNumber: 2,
					Filepath:   "abc.py",
					From:       "foo",
				},
			},
		},
		// align to https://docs.python.org/3/reference/simple_stmts.html#index-34
		{
			name: "complex import",
			code: "from unittest import *\nfrom foo import (bar as c, baz, qux as d)\nfrom . import abc",
			result: []Module{
				{
					Name:       "unittest.*",
					LineNumber: 1,
					From:       "unittest",
				},
				{
					Name:       "foo.bar",
					LineNumber: 2,
					From:       "foo",
				},
				{
					Name:       "foo.baz",
					LineNumber: 2,
					From:       "foo",
				},
				{
					Name:       "foo.qux",
					LineNumber: 2,
					From:       "foo",
				},
			},
		},
	}
	for _, u := range units {
		t.Run(u.name, func(t *testing.T) {
			p := NewFileParser()
			code := []byte(u.code)
			p.SetCodeAndFile(code, "", u.filepath)
			output, err := p.Parse(context.Background())
			assert.NoError(t, err)
			assert.Equal(t, u.result, output.Modules)
		})
	}
}

func TestParsePytestPlugins(t *testing.T) {
	t.Parallel()
	units := []struct {
		name string
		code string
		want []string
	}{
		{"string", `pytest_plugins = "foo.bar"`, []string{"foo.bar"}},
		{"single quotes", `pytest_plugins = 'foo.bar'`, []string{"foo.bar"}},
		{"list", `pytest_plugins = ["foo.bar", 'foo.baz']`, []string{"foo.bar", "foo.baz"}},
		{"tuple", `pytest_plugins = ("foo.bar", "foo.baz")`, []string{"foo.bar", "foo.baz"}},
		{"unparenthesized tuple", `pytest_plugins = "foo.bar", "foo.baz"`, []string{"foo.bar", "foo.baz"}},
		{"one element tuple", `pytest_plugins = ("foo.bar",)`, []string{"foo.bar"}},
		{"parentheses", `pytest_plugins = (("foo.bar"))`, []string{"foo.bar"}},
		{"parenthesized list", `pytest_plugins = (["foo.bar"])`, []string{"foo.bar"}},
		{"leading parenthesis comment", "pytest_plugins = (\n# comment\n'foo.bar'\n)", []string{"foo.bar"}},
		{"leading list parenthesis comment", "pytest_plugins = (\n# comment\n['foo.bar']\n)", []string{"foo.bar"}},
		{"parenthesized list item comment", "pytest_plugins = [(\n# comment\n'foo.bar'\n)]", []string{"foo.bar"}},
		{"annotated", `pytest_plugins: list[str] = ["foo.bar"]`, []string{"foo.bar"}},
		{"chained left", `pytest_plugins = other = ["foo.bar"]`, []string{"foo.bar"}},
		{"chained right", `other = pytest_plugins = ["foo.bar"]`, []string{"foo.bar"}},
		{"comma separated string", `pytest_plugins = "foo.bar,foo.baz"`, []string{"foo.bar", "foo.baz"}},
		{"comma in list string", `pytest_plugins = ["foo.bar,foo.baz"]`, []string{"foo.bar,foo.baz"}},
		{"raw", `pytest_plugins = R"foo.bar"`, []string{"foo.bar"}},
		{"unicode prefix", `pytest_plugins = u'foo.bar'`, []string{"foo.bar"}},
		{"triple quotes", `pytest_plugins = """foo.bar"""`, []string{"foo.bar"}},
		{"triple single quotes", `pytest_plugins = '''foo.bar'''`, []string{"foo.bar"}},
		{"raw triple quotes", `pytest_plugins = r'''foo.bar'''`, []string{"foo.bar"}},
		{"non-ASCII module", `pytest_plugins = 'foo.café'`, []string{"foo.café"}},
		{"implicit concatenation", `pytest_plugins = "foo." 'bar'`, []string{"foo.bar"}},
		{"concatenation with comment", "pytest_plugins = (\"foo.\" # comment\n'bar')", []string{"foo.bar"}},
		{"escape sequences", `pytest_plugins = ["foo\x2ebar", 'foo\u002ebaz', "foo\U0000002equx", 'foo\056last']`, []string{"foo.bar", "foo.baz", "foo.qux", "foo.last"}},
		{"short octal", `pytest_plugins = 'foo\7bar'`, []string{"foo\abar"}},
		{"octal non-ASCII", `pytest_plugins = 'foo.\351'`, []string{"foo.é"}},
		{"hex non-ASCII", `pytest_plugins = 'foo.\xe9'`, []string{"foo.é"}},
		{"escaped backslash", `pytest_plugins = 'foo\\bar'`, []string{`foo\bar`}},
		{"control escapes", `pytest_plugins = '\a\b\f\n\r\t\v'`, []string{"\a\b\f\n\r\t\v"}},
		{"surrogate escape", `pytest_plugins = 'foo.\ud800'`, nil},
		{"out of range Unicode escape", `pytest_plugins = 'foo.\U00110000'`, nil},
		{"escaped quotes", `pytest_plugins = ["foo\"bar", 'foo\'baz']`, []string{"foo\"bar", "foo'baz"}},
		{"unrecognized escape", `pytest_plugins = 'foo\qbar'`, []string{`foo\qbar`}},
		{"raw escape", `pytest_plugins = r'foo\u002ebar'`, []string{`foo\u002ebar`}},
		{"continued string", "pytest_plugins = 'foo.\\\nbar'", []string{"foo.bar"}},
		{"continued CRLF string", "pytest_plugins = 'foo.\\\r\nbar'", []string{"foo.bar"}},
		{"conditional", "if condition:\n    pytest_plugins = ['foo.bar']\nelse:\n    pytest_plugins = ['foo.baz']", []string{"foo.bar", "foo.baz"}},
		{"reassignment", "pytest_plugins = ['foo.bar']\npytest_plugins = ['foo.baz']", []string{"foo.bar", "foo.baz"}},
		{"empty string", `pytest_plugins = ""`, nil},
		{"empty list", `pytest_plugins = []`, nil},
		{"empty tuple", `pytest_plugins = ()`, nil},
		{"comments in empty list", "pytest_plugins = [\n# comment\n]", nil},
		{"none", `pytest_plugins = None`, nil},
		{"annotation only", `pytest_plugins: list[str]`, nil},
		{"different name", `other_plugins = ["foo.bar"]`, nil},
		{"attribute", `module.pytest_plugins = ["foo.bar"]`, nil},
		{"unpacking", `pytest_plugins, other = ["foo.bar", "foo.baz"]`, nil},
		{"function local", "def f():\n    pytest_plugins = ['foo.bar']", nil},
		{"class local", "class C:\n    pytest_plugins = ['foo.bar']", nil},
		{"async function local", "async def f():\n    pytest_plugins = ['foo.bar']", nil},
		{"decorated function local", "@decorate\ndef f():\n    pytest_plugins = ['foo.bar']", nil},
		{"scope restored", "def f():\n    pytest_plugins = ['foo.local']\npytest_plugins = ['foo.bar']", []string{"foo.bar"}},
		{"ordinary imports remain local", "def f():\n    import foo.bar\n    pytest_plugins = ['foo.local']", []string{"foo.bar"}},
		{"dynamic call", `pytest_plugins = plugins()`, nil},
		{"dynamic identifier", `pytest_plugins = plugins`, nil},
		{"dynamic list", `pytest_plugins = ["foo.bar", plugin]`, nil},
		{"dynamic concatenated string", `pytest_plugins = "foo." f"{name}"`, nil},
		{"nested list", `pytest_plugins = [["foo.bar"]]`, nil},
		{"starred list", `pytest_plugins = ["foo.bar", *plugins]`, nil},
		{"comprehension", `pytest_plugins = [name for name in plugins]`, nil},
		{"addition", `pytest_plugins = ["foo.bar"] + plugins`, nil},
		{"augmented assignment", `pytest_plugins += ["foo.bar"]`, nil},
		{"set", `pytest_plugins = {"foo.bar"}`, nil},
		{"bytes", `pytest_plugins = b"foo.bar"`, nil},
		{"f-string", `pytest_plugins = f"foo.{name}"`, nil},
		{"constant f-string", `pytest_plugins = f"foo.bar"`, nil},
		{"malformed declaration", `pytest_plugins = [`, nil},
		{"malformed list", `pytest_plugins = ["foo.bar",`, nil},
		{"invalid escape", `pytest_plugins = "foo\xZZbar"`, nil},
		{"named Unicode escape", `pytest_plugins = "foo\N{FULL STOP}bar"`, nil},
	}
	for _, unit := range units {
		t.Run(unit.name, func(t *testing.T) {
			p := NewFileParser()
			p.SetCodeAndFile([]byte(unit.code), "tests", "example_test.py")
			output, err := p.Parse(context.Background())
			assert.NoError(t, err)
			var names []string
			for _, module := range output.Modules {
				names = append(names, module.Name)
				assert.Equal(t, filepath.Join("tests", "example_test.py"), module.Filepath)
				assert.Empty(t, module.From)
				assert.False(t, module.TypeCheckingOnly)
			}
			assert.Equal(t, unit.want, names)
		})
	}
}

func TestPytestPluginsLocationsAndComments(t *testing.T) {
	t.Parallel()
	p := NewFileParser()
	p.SetCodeAndFile([]byte("pytest_plugins = [\n    'foo.bar', # gazelle:ignore foo.bar\n    'foo.baz',\n]\nif TYPE_CHECKING:\n    pytest_plugins = 'foo.typing'\n"), "", "conftest.py")
	output, err := p.Parse(context.Background())
	assert.NoError(t, err)
	assert.Equal(t, []Module{
		{Name: "foo.bar", LineNumber: 2, Filepath: "conftest.py"},
		{Name: "foo.baz", LineNumber: 3, Filepath: "conftest.py"},
		{Name: "foo.typing", LineNumber: 6, Filepath: "conftest.py", TypeCheckingOnly: true},
	}, output.Modules)
	assert.Equal(t, []Comment{"# gazelle:ignore foo.bar"}, output.Comments)
}

func TestParseComments(t *testing.T) {
	t.Parallel()
	units := []struct {
		name   string
		code   string
		result []Comment
	}{
		{
			name:   "not has comment",
			code:   "a = 1\nb = 2",
			result: nil,
		},
		{
			name:   "has comment",
			code:   "# a = 1\n# b = 2",
			result: []Comment{"# a = 1", "# b = 2"},
		},
		{
			name:   "has comment in if",
			code:   "if True:\n  # a = 1\n  # b = 2",
			result: []Comment{"# a = 1", "# b = 2"},
		},
		{
			name:   "has comment inline",
			code:   "import os# 123\nfrom pathlib import Path as b#456",
			result: []Comment{"# 123", "#456"},
		},
	}
	for _, u := range units {
		t.Run(u.name, func(t *testing.T) {
			p := NewFileParser()
			code := []byte(u.code)
			p.SetCodeAndFile(code, "", "")
			output, err := p.Parse(context.Background())
			assert.NoError(t, err)
			assert.Equal(t, u.result, output.Comments)
		})
	}
}

func TestParseMain(t *testing.T) {
	t.Parallel()
	units := []struct {
		name   string
		code   string
		result bool
	}{
		{
			name:   "not has main",
			code:   "a = 1\nb = 2",
			result: false,
		},
		{
			name: "has main in function",
			code: `def foo():
	if __name__ == "__main__":
		a = 3
`,
			result: false,
		},
		{
			name: "has main",
			code: `
import unittest

from lib import main


class ExampleTest(unittest.TestCase):
    def test_main(self):
        self.assertEqual(
            "",
            main([["A", 1], ["B", 2]]),
        )


if __name__ == "__main__":
    unittest.main()
`,
			result: true,
		},
	}
	for _, u := range units {
		t.Run(u.name, func(t *testing.T) {
			p := NewFileParser()
			code := []byte(u.code)
			p.SetCodeAndFile(code, "", "")
			output, err := p.Parse(context.Background())
			assert.NoError(t, err)
			assert.Equal(t, u.result, output.HasMain)
		})
	}
}

func TestParseFull(t *testing.T) {
	p := NewFileParser()
	code := []byte(`from bar import abc`)
	p.SetCodeAndFile(code, "foo", "a.py")
	output, err := p.Parse(context.Background())
	assert.NoError(t, err)
	assert.Equal(t, ParserOutput{
		Modules:  []Module{{Name: "bar.abc", LineNumber: 1, Filepath: "foo/a.py", From: "bar"}},
		Comments: nil,
		HasMain:  false,
		FileName: "a.py",
	}, *output)
}

func TestTypeCheckingImports(t *testing.T) {
	code := `
import sys
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import boto3
    from rest_framework import serializers

def example_function():
    _ = sys.version_info
`
	p := NewFileParser()
	p.SetCodeAndFile([]byte(code), "", "test.py")

	result, err := p.Parse(context.Background())
	if err != nil {
		t.Fatalf("Failed to parse: %v", err)
	}

	// Check that we found the expected modules
	expectedModules := map[string]bool{
		"sys":                        false,
		"typing.TYPE_CHECKING":       false,
		"boto3":                      true,
		"rest_framework.serializers": true,
	}

	for _, mod := range result.Modules {
		if expected, exists := expectedModules[mod.Name]; exists {
			if mod.TypeCheckingOnly != expected {
				t.Errorf("Module %s: expected TypeCheckingOnly=%v, got %v", mod.Name, expected, mod.TypeCheckingOnly)
			}
		}
	}
}

func TestParseImportStatements_MultilineWithBackslashAndWhitespace(t *testing.T) {
	t.Parallel()
	t.Run("multiline from import", func(t *testing.T) {
		p := NewFileParser()
		code := []byte(`from foo.bar.\
    baz import (
    Something,
    AnotherThing
)

from foo\
	.test import (
    Foo,
    Bar
)
`)
		p.SetCodeAndFile(code, "", "test.py")
		output, err := p.Parse(context.Background())
		assert.NoError(t, err)
		// Updated expected to match parser output
		expected := []Module{
			{
				Name:       "foo.bar.baz.Something",
				LineNumber: 3,
				Filepath:   "test.py",
				From:       "foo.bar.baz",
			},
			{
				Name:       "foo.bar.baz.AnotherThing",
				LineNumber: 4,
				Filepath:   "test.py",
				From:       "foo.bar.baz",
			},
			{
				Name:       "foo.test.Foo",
				LineNumber: 9,
				Filepath:   "test.py",
				From:       "foo.test",
			},
			{
				Name:       "foo.test.Bar",
				LineNumber: 10,
				Filepath:   "test.py",
				From:       "foo.test",
			},
		}
		assert.ElementsMatch(t, expected, output.Modules)
	})
	t.Run("multiline import", func(t *testing.T) {
		p := NewFileParser()
		code := []byte(`import foo.bar.\
    baz
`)
		p.SetCodeAndFile(code, "", "test.py")
		output, err := p.Parse(context.Background())
		assert.NoError(t, err)
		// Updated expected to match parser output
		expected := []Module{
			{
				Name:       "foo.bar.baz",
				LineNumber: 1,
				Filepath:   "test.py",
				From:       "",
			},
		}
		assert.ElementsMatch(t, expected, output.Modules)
	})
	t.Run("windows line endings", func(t *testing.T) {
		p := NewFileParser()
		code := []byte("from foo.bar.\r\n baz import (\r\n    Something,\r\n    AnotherThing\r\n)\r\n")
		p.SetCodeAndFile(code, "", "test.py")
		output, err := p.Parse(context.Background())
		assert.NoError(t, err)
		// Updated expected to match parser output
		expected := []Module{
			{
				Name:       "foo.bar.baz.Something",
				LineNumber: 3,
				Filepath:   "test.py",
				From:       "foo.bar.baz",
			},
			{
				Name:       "foo.bar.baz.AnotherThing",
				LineNumber: 4,
				Filepath:   "test.py",
				From:       "foo.bar.baz",
			},
		}
		assert.ElementsMatch(t, expected, output.Modules)
	})
}
