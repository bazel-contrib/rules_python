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
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	bzl "github.com/bazelbuild/buildtools/build"
	sitter "github.com/smacker/go-tree-sitter"
	"github.com/smacker/go-tree-sitter/python"
)

const (
	sitterNodeTypeString              = "string"
	sitterNodeTypeComment             = "comment"
	sitterNodeTypeIdentifier          = "identifier"
	sitterNodeTypeDottedName          = "dotted_name"
	sitterNodeTypeIfStatement         = "if_statement"
	sitterNodeTypeAliasedImport       = "aliased_import"
	sitterNodeTypeWildcardImport      = "wildcard_import"
	sitterNodeTypeImportStatement     = "import_statement"
	sitterNodeTypeComparisonOperator  = "comparison_operator"
	sitterNodeTypeImportFromStatement = "import_from_statement"
)

type ParserOutput struct {
	FileName string
	Modules  []Module
	Comments []Comment
	HasMain  bool
}

type FileParser struct {
	code                []byte
	relFilepath         string
	output              ParserOutput
	inTypeCheckingBlock bool
	inLocalScope        bool
}

func NewFileParser() *FileParser {
	return &FileParser{}
}

// ParseCode instantiates a new tree-sitter Parser and parses the python code, returning
// the tree-sitter RootNode.
// It prints a warning if parsing fails.
func ParseCode(code []byte, path string) (*sitter.Node, error) {
	parser := sitter.NewParser()
	parser.SetLanguage(python.GetLanguage())

	tree, err := parser.ParseCtx(context.Background(), nil, code)
	if err != nil {
		return nil, err
	}

	root := tree.RootNode()
	if !root.HasError() {
		return root, nil
	}

	log.Printf("WARNING: failed to parse %q. The resulting BUILD target may be incorrect.", path)

	// Note: we intentionally do not return an error even when root.HasError because the parse
	// failure may be in some part of the code that Gazelle doesn't care about.
	verbose, envExists := os.LookupEnv("RULES_PYTHON_GAZELLE_VERBOSE")
	if !envExists || verbose != "1" {
		return root, nil
	}

	for i := 0; i < int(root.ChildCount()); i++ {
		child := root.Child(i)
		if child.IsError() {
			// Example logs:
			// gazelle: Parse error at {Row:1 Column:0}:
			// def search_one_more_level[T]():
			log.Printf("Parse error at %+v:\n%+v", child.StartPoint(), child.Content(code))
			// Log the internal tree-sitter representation of what was parsed. Eg:
			// gazelle: The above was parsed as: (ERROR (identifier) (call function: (list (identifier)) arguments: (argument_list)))
			log.Printf("The above was parsed as: %v", child.String())
		}
	}

	return root, nil
}

// parseMain returns true if the python file has an `if __name__ == "__main__":` block,
// which is a common idiom for python scripts/binaries.
func (p *FileParser) parseMain(ctx context.Context, node *sitter.Node) bool {
	for i := 0; i < int(node.ChildCount()); i++ {
		if err := ctx.Err(); err != nil {
			return false
		}
		child := node.Child(i)
		if child.Type() == sitterNodeTypeIfStatement &&
			child.Child(1).Type() == sitterNodeTypeComparisonOperator && child.Child(1).Child(1).Type() == "==" {
			statement := child.Child(1)
			a, b := statement.Child(0), statement.Child(2)
			// convert "'__main__' == __name__" to "__name__ == '__main__'"
			if b.Type() == sitterNodeTypeIdentifier {
				a, b = b, a
			}
			if a.Type() == sitterNodeTypeIdentifier && a.Content(p.code) == "__name__" &&
				b.Type() == sitterNodeTypeString && string(p.code[b.StartByte()+1:b.EndByte()-1]) == "__main__" {
				return true
			}
		}
	}
	return false
}

// parseImportStatement parses a node for an import statement, returning a `Module` and a boolean
// representing if the parse was OK or not.
func parseImportStatement(node *sitter.Node, code []byte) (Module, bool) {
	switch node.Type() {
	case sitterNodeTypeDottedName:
		return Module{
			Name:       node.Content(code),
			LineNumber: node.StartPoint().Row + 1,
		}, true
	case sitterNodeTypeAliasedImport:
		return parseImportStatement(node.Child(0), code)
	case sitterNodeTypeWildcardImport:
		return Module{
			Name:       "*",
			LineNumber: node.StartPoint().Row + 1,
		}, true
	}
	return Module{}, false
}

// cleanImportString removes backslashes and all whitespace from the string.
func cleanImportString(s string) string {
	s = strings.ReplaceAll(s, "\r\n", "")
	s = strings.ReplaceAll(s, "\\", "")
	s = strings.ReplaceAll(s, " ", "")
	s = strings.ReplaceAll(s, "\n", "")
	s = strings.ReplaceAll(s, "\t", "")
	return s
}

// parseImportStatements parses a node for import statements, returning true if the node is
// an import statement. It updates FileParser.output.Modules with the `module` that the
// import represents.
func (p *FileParser) parseImportStatements(node *sitter.Node) bool {
	if node.Type() == sitterNodeTypeImportStatement {
		for j := 1; j < int(node.ChildCount()); j++ {
			m, ok := parseImportStatement(node.Child(j), p.code)
			if !ok {
				continue
			}
			m.From = cleanImportString(m.From)
			m.Name = cleanImportString(m.Name)
			m.Filepath = p.relFilepath
			m.TypeCheckingOnly = p.inTypeCheckingBlock
			if strings.HasPrefix(m.Name, ".") {
				continue
			}
			p.output.Modules = append(p.output.Modules, m)
		}
	} else if node.Type() == sitterNodeTypeImportFromStatement {
		from := node.Child(1).Content(p.code)
		from = cleanImportString(from)
		// If the import is from the current package, we don't need to add it to the modules i.e. from . import Class1.
		// If the import is from a different relative package i.e. from .package1 import foo, we need to add it to the modules.
		if from == "." {
			return true
		}
		for j := 3; j < int(node.ChildCount()); j++ {
			m, ok := parseImportStatement(node.Child(j), p.code)
			if !ok {
				continue
			}
			m.Filepath = p.relFilepath
			m.From = from
			m.Name = cleanImportString(m.Name)
			m.Name = fmt.Sprintf("%s.%s", from, m.Name)
			m.TypeCheckingOnly = p.inTypeCheckingBlock
			p.output.Modules = append(p.output.Modules, m)
		}
	} else {
		return false
	}
	return true
}

// parseComments parses a node for comments, returning true if the node is a comment.
// It updates FileParser.output.Comments with the parsed comment.
func (p *FileParser) parseComments(node *sitter.Node) bool {
	if node.Type() == sitterNodeTypeComment {
		p.output.Comments = append(p.output.Comments, Comment(node.Content(p.code)))
		return true
	}
	return false
}

func (p *FileParser) SetCodeAndFile(code []byte, relPackagePath, filename string) {
	p.code = code
	p.relFilepath = filepath.Join(relPackagePath, filename)
	p.output.FileName = filename
}

// isTypeCheckingBlock returns true if the given node is an `if TYPE_CHECKING:` block.
func (p *FileParser) isTypeCheckingBlock(node *sitter.Node) bool {
	if node.Type() != sitterNodeTypeIfStatement || node.ChildCount() < 2 {
		return false
	}

	condition := node.Child(1)

	// Handle `if TYPE_CHECKING:`
	if condition.Type() == sitterNodeTypeIdentifier && condition.Content(p.code) == "TYPE_CHECKING" {
		return true
	}

	// Handle `if typing.TYPE_CHECKING:`
	if condition.Type() == "attribute" && condition.ChildCount() >= 3 {
		object := condition.Child(0)
		attr := condition.Child(2)
		if object.Type() == sitterNodeTypeIdentifier && object.Content(p.code) == "typing" &&
			attr.Type() == sitterNodeTypeIdentifier && attr.Content(p.code) == "TYPE_CHECKING" {
			return true
		}
	}

	return false
}

// pytestPluginExpression unwraps parentheses, ignoring comments before the value.
func pytestPluginExpression(node *sitter.Node) *sitter.Node {
	for node != nil && node.Type() == "parenthesized_expression" {
		var expression *sitter.Node
		for i := 0; i < int(node.NamedChildCount()); i++ {
			child := node.NamedChild(i)
			if child.Type() != sitterNodeTypeComment {
				expression = child
				break
			}
		}
		node = expression
	}
	return node
}

// pytestPluginString evaluates literal Python strings without executing Python.
// Dynamic expressions, bytes, f-strings, and named Unicode escapes are not evaluated.
func pytestPluginString(node *sitter.Node, code []byte) (string, bool) {
	node = pytestPluginExpression(node)
	if node == nil {
		return "", false
	}
	if node.Type() == "concatenated_string" {
		var value strings.Builder
		for i := 0; i < int(node.NamedChildCount()); i++ {
			child := node.NamedChild(i)
			if child.Type() == sitterNodeTypeComment {
				continue
			}
			part, ok := pytestPluginString(child, code)
			if !ok {
				return "", false
			}
			value.WriteString(part)
		}
		return value.String(), true
	}
	if node.Type() != sitterNodeTypeString || node.HasError() {
		return "", false
	}
	literal := node.Content(code)
	quote := strings.IndexAny(literal, "\"'")
	if quote < 0 {
		return "", false
	}
	prefix := strings.ToLower(literal[:quote])
	if prefix != "" && prefix != "r" && prefix != "u" {
		return "", false
	}
	// Python normalizes source newlines even inside raw string literals.
	content := strings.ReplaceAll(literal[quote:], "\r\n", "\n")
	content = strings.ReplaceAll(content, "\r", "\n")
	if prefix == "r" {
		value, _, err := bzl.Unquote("r" + content)
		return value, err == nil
	}
	if !strings.Contains(content, "\\") {
		value, _, err := bzl.Unquote(content)
		return value, err == nil
	}
	// Buildtools already handles Python-style quotes and escapes. Normalize
	// newlines and byte escapes to preserve Python 3's Unicode string semantics:
	// buildtools interprets hex and octal escapes as bytes instead of code points.
	var normalized strings.Builder
	for len(content) > 0 {
		if content[0] != '\\' {
			normalized.WriteByte(content[0])
			content = content[1:]
			continue
		}
		if len(content) < 2 {
			return "", false
		}
		if content[1] == 'N' {
			return "", false
		}
		if content[1] == 'x' || (content[1] >= '0' && content[1] <= '7') {
			end := 2
			base := 8
			start := 1
			if content[1] == 'x' {
				end, start, base = 4, 2, 16
				if len(content) < end {
					return "", false
				}
			} else {
				for end < len(content) && end < 4 && content[end] >= '0' && content[end] <= '7' {
					end++
				}
			}
			r, err := strconv.ParseUint(content[start:end], base, 16)
			if err != nil {
				return "", false
			}
			fmt.Fprintf(&normalized, "\\u%04x", r)
			content = content[end:]
			continue
		}
		normalized.WriteString(content[:2])
		content = content[2:]
	}
	value, _, err := bzl.Unquote(normalized.String())
	return value, err == nil
}

// parsePytestPlugins treats static module-level pytest_plugins declarations as
// imports. As with conditional imports, all statically declared alternatives are
// included; Python code is never executed to determine the active branch.
func (p *FileParser) parsePytestPlugins(node *sitter.Node) {
	if p.inLocalScope || node.Type() != "assignment" {
		return
	}
	left := node.ChildByFieldName("left")
	if left == nil || left.Type() != sitterNodeTypeIdentifier || left.Content(p.code) != "pytest_plugins" {
		return
	}
	right := node.ChildByFieldName("right")
	for right != nil && right.Type() == "assignment" {
		right = right.ChildByFieldName("right")
	}
	right = pytestPluginExpression(right)
	if right == nil || right.HasError() {
		return
	}
	add := func(value string, node *sitter.Node) {
		if value != "" {
			p.output.Modules = append(p.output.Modules, Module{
				Name:             value,
				LineNumber:       node.StartPoint().Row + 1,
				Filepath:         p.relFilepath,
				TypeCheckingOnly: p.inTypeCheckingBlock,
				PytestPlugin:     true,
			})
		}
	}
	if right.Type() == "list" || right.Type() == "tuple" || right.Type() == "expression_list" {
		for i := 0; i < int(right.NamedChildCount()); i++ {
			child := right.NamedChild(i)
			if child.Type() == sitterNodeTypeComment {
				continue
			}
			value, ok := pytestPluginString(child, p.code)
			if !ok {
				continue
			}
			add(value, child)
		}
	} else {
		value, ok := pytestPluginString(right, p.code)
		if !ok {
			return
		}
		// Pytest also accepts comma-separated module names in a single string.
		for _, name := range strings.Split(value, ",") {
			add(name, right)
		}
	}
}

func (p *FileParser) parse(ctx context.Context, node *sitter.Node) {
	if node == nil {
		return
	}

	// Check if this is a TYPE_CHECKING block
	wasInTypeCheckingBlock := p.inTypeCheckingBlock
	wasInLocalScope := p.inLocalScope
	defer func() {
		p.inTypeCheckingBlock = wasInTypeCheckingBlock
		p.inLocalScope = wasInLocalScope
	}()
	if node.Type() == "function_definition" || node.Type() == "class_definition" || node.Type() == "lambda" {
		p.inLocalScope = true
	}
	if p.isTypeCheckingBlock(node) {
		p.inTypeCheckingBlock = true
	}

	for i := 0; i < int(node.ChildCount()); i++ {
		if err := ctx.Err(); err != nil {
			return
		}
		child := node.Child(i)
		p.parsePytestPlugins(child)
		if p.parseImportStatements(child) {
			continue
		}
		if p.parseComments(child) {
			continue
		}
		p.parse(ctx, child)
	}

}

func (p *FileParser) Parse(ctx context.Context) (*ParserOutput, error) {
	rootNode, err := ParseCode(p.code, p.relFilepath)
	if err != nil {
		return nil, err
	}

	p.output.HasMain = p.parseMain(ctx, rootNode)

	p.parse(ctx, rootNode)
	return &p.output, nil
}

func (p *FileParser) ParseFile(ctx context.Context, repoRoot, relPackagePath, filename string) (*ParserOutput, error) {
	code, err := os.ReadFile(filepath.Join(repoRoot, relPackagePath, filename))
	if err != nil {
		return nil, err
	}
	p.SetCodeAndFile(code, relPackagePath, filename)
	return p.Parse(ctx)
}
