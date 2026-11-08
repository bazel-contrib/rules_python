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
	"strings"

	sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_python "github.com/tree-sitter/tree-sitter-python/bindings/go"
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
}

func NewFileParser() *FileParser {
	return &FileParser{}
}

// parseCodeToTree instantiates a new tree-sitter Parser and parses the Python code,
// returning the parsed tree-sitter Tree. Callers are responsible for calling Close()
// on the returned Tree to release its underlying C resources when finished.
// It logs a warning if the syntax tree contains parse errors.
func parseCodeToTree(code []byte, path string) (*sitter.Tree, error) {
	parser := sitter.NewParser()
	defer parser.Close()
	if err := parser.SetLanguage(sitter.NewLanguage(tree_sitter_python.Language())); err != nil {
		return nil, err
	}

	tree := parser.ParseCtx(context.Background(), code, nil)
	if tree == nil {
		return nil, fmt.Errorf("failed to parse %q", path)
	}

	root := tree.RootNode()
	if !root.HasError() {
		return tree, nil
	}

	log.Printf("WARNING: failed to parse %q. The resulting BUILD target may be incorrect.", path)

	// Note: we intentionally do not return an error even when root.HasError because the parse
	// failure may be in some part of the code that Gazelle doesn't care about.
	verbose, envExists := os.LookupEnv("RULES_PYTHON_GAZELLE_VERBOSE")
	if !envExists || verbose != "1" {
		return tree, nil
	}

	for i := uint(0); i < root.ChildCount(); i++ {
		child := root.Child(i)
		if child.IsError() {
			// Example logs:
			// gazelle: Parse error at {Row:1 Column:0}:
			// def search_one_more_level[T]():
			log.Printf("Parse error at %+v:\n%+v", child.StartPosition(), child.Utf8Text(code))
			// Log the internal tree-sitter representation of what was parsed. Eg:
			// gazelle: The above was parsed as: (ERROR (identifier) (call function: (list (identifier)) arguments: (argument_list)))
			log.Printf("The above was parsed as: %v", child.ToSexp())
		}
	}

	return tree, nil
}

// ParseCode instantiates a new tree-sitter Parser and parses the python code, returning
// the tree-sitter RootNode.
// It prints a warning if parsing fails.
func ParseCode(code []byte, path string) (*sitter.Node, error) {
	tree, err := parseCodeToTree(code, path)
	if err != nil {
		return nil, err
	}
	return tree.RootNode(), nil
}

// parseMain returns true if the python file has an `if __name__ == "__main__":` block,
// which is a common idiom for python scripts/binaries.
func (p *FileParser) parseMain(ctx context.Context, node *sitter.Node) bool {
	for i := uint(0); i < node.ChildCount(); i++ {
		if err := ctx.Err(); err != nil {
			return false
		}
		child := node.Child(i)
		if child.Kind() == sitterNodeTypeIfStatement &&
			child.Child(1).Kind() == sitterNodeTypeComparisonOperator && child.Child(1).Child(1).Kind() == "==" {
			statement := child.Child(1)
			a, b := statement.Child(0), statement.Child(2)
			// convert "'__main__' == __name__" to "__name__ == '__main__'"
			if b.Kind() == sitterNodeTypeIdentifier {
				a, b = b, a
			}
			if a.Kind() == sitterNodeTypeIdentifier && a.Utf8Text(p.code) == "__name__" &&
				b.Kind() == sitterNodeTypeString && string(p.code[b.StartByte()+1:b.EndByte()-1]) == "__main__" {
				return true
			}
		}
	}
	return false
}

// parseImportStatement parses a node for an import statement, returning a `Module` and a boolean
// representing if the parse was OK or not.
func parseImportStatement(node *sitter.Node, code []byte) (Module, bool) {
	switch node.Kind() {
	case sitterNodeTypeDottedName:
		return Module{
			Name:       node.Utf8Text(code),
			LineNumber: uint32(node.StartPosition().Row) + 1,
		}, true
	case sitterNodeTypeAliasedImport:
		return parseImportStatement(node.Child(0), code)
	case sitterNodeTypeWildcardImport:
		return Module{
			Name:       "*",
			LineNumber: uint32(node.StartPosition().Row) + 1,
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
	if node.Kind() == sitterNodeTypeImportStatement {
		for j := uint(1); j < node.ChildCount(); j++ {
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
	} else if node.Kind() == sitterNodeTypeImportFromStatement {
		from := node.Child(1).Utf8Text(p.code)
		from = cleanImportString(from)
		// If the import is from the current package, we don't need to add it to the modules i.e. from . import Class1.
		// If the import is from a different relative package i.e. from .package1 import foo, we need to add it to the modules.
		if from == "." {
			return true
		}
		for j := uint(3); j < node.ChildCount(); j++ {
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
	if node.Kind() == sitterNodeTypeComment {
		p.output.Comments = append(p.output.Comments, Comment(node.Utf8Text(p.code)))
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
	if node.Kind() != sitterNodeTypeIfStatement || node.ChildCount() < 2 {
		return false
	}

	condition := node.Child(1)

	// Handle `if TYPE_CHECKING:`
	if condition.Kind() == sitterNodeTypeIdentifier && condition.Utf8Text(p.code) == "TYPE_CHECKING" {
		return true
	}

	// Handle `if typing.TYPE_CHECKING:`
	if condition.Kind() == "attribute" && condition.ChildCount() >= 3 {
		object := condition.Child(0)
		attr := condition.Child(2)
		if object.Kind() == sitterNodeTypeIdentifier && object.Utf8Text(p.code) == "typing" &&
			attr.Kind() == sitterNodeTypeIdentifier && attr.Utf8Text(p.code) == "TYPE_CHECKING" {
			return true
		}
	}

	return false
}

func (p *FileParser) parse(ctx context.Context, node *sitter.Node) {
	if node == nil {
		return
	}

	// Check if this is a TYPE_CHECKING block
	wasInTypeCheckingBlock := p.inTypeCheckingBlock
	if p.isTypeCheckingBlock(node) {
		p.inTypeCheckingBlock = true
	}

	for i := uint(0); i < node.ChildCount(); i++ {
		if err := ctx.Err(); err != nil {
			return
		}
		child := node.Child(i)
		if p.parseImportStatements(child) {
			continue
		}
		if p.parseComments(child) {
			continue
		}
		p.parse(ctx, child)
	}

	// Restore the previous state
	p.inTypeCheckingBlock = wasInTypeCheckingBlock
}

func (p *FileParser) Parse(ctx context.Context) (*ParserOutput, error) {
	tree, err := parseCodeToTree(p.code, p.relFilepath)
	if err != nil {
		return nil, err
	}
	defer tree.Close()
	rootNode := tree.RootNode()

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
