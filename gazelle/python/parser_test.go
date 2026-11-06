package python

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/emirpasic/gods/sets/treeset"
	godsutils "github.com/emirpasic/gods/utils"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseIncludePytestConftestAnnotations(t *testing.T) {
	t.Parallel()

	boolPointer := func(value bool) *bool {
		return &value
	}
	tests := []struct {
		name      string
		contents  []string
		expected  *bool
		expectErr string
	}{
		{
			name:     "all unset",
			contents: []string{"", ""},
		},
		{
			name:     "false and unset",
			contents: []string{"# gazelle:include_pytest_conftest false", ""},
			expected: boolPointer(false),
		},
		{
			name:     "true and unset",
			contents: []string{"", "# gazelle:include_pytest_conftest true"},
			expected: boolPointer(true),
		},
		{
			name: "matching false values",
			contents: []string{
				"# gazelle:include_pytest_conftest false",
				"# gazelle:include_pytest_conftest false",
				"",
			},
			expected: boolPointer(false),
		},
		{
			name: "matching true values",
			contents: []string{
				"# gazelle:include_pytest_conftest true",
				"",
				"# gazelle:include_pytest_conftest true",
			},
			expected: boolPointer(true),
		},
		{
			name: "conflicting values",
			contents: []string{
				"# gazelle:include_pytest_conftest false",
				"",
				"# gazelle:include_pytest_conftest true",
			},
			expectErr: "conflicting values for the \"include_pytest_conftest\" annotation " +
				"across Python source files",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			repoRoot := t.TempDir()
			filenames := treeset.NewWith(godsutils.StringComparator)
			for index, contents := range test.contents {
				filename := string(rune('a'+index)) + "_test.py"
				require.NoError(t, os.WriteFile(filepath.Join(repoRoot, filename), []byte(contents), 0o600))
				filenames.Add(filename)
			}

			parser := newPython3Parser(repoRoot, "", func(string) bool { return false })
			_, _, annotations, err := parser.parse(filenames)
			if test.expectErr != "" {
				assert.EqualError(t, err, test.expectErr)
				return
			}

			require.NoError(t, err)
			assert.Equal(t, test.expected, annotations.includePytestConftest)
		})
	}
}
