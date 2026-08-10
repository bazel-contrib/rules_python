# Pyrefly `bad-override` Analysis and Resolution Plan

This document analyzes all 15 `# pyrefly: ignore[bad-override]` suppressions
in the codebase. Each section provides:
1. The exact file location and line number.
2. The parent class and method being overridden.
3. The Pyrefly diagnostic produced when the suppression comment is removed.
4. The root cause explaining the signature / Liskov Substitution Principle (LSP)
   mismatch.
5. A concrete suggestion on how to fix the signature/overload to be type-correct.

---

## 1. `Path.open` (`python/runfiles/runfiles.py:326`)

* **File Location**: [`python/runfiles/runfiles.py:326`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/python/runfiles/runfiles.py#L326)
* **Parent Class**: `pathlib.Path` (`pathlib.Path.open`)

### Error Without Suppression
```text
ERROR Class member `Path.open` overrides parent class `Path` in an inconsistent manner [bad-override]
   --> python/runfiles/runfiles.py:326:9
    |
326 |     def open(
    |         ^^^^
    |
  `Path.open` has type `(self: Path, mode: str = 'r', buffering: int = -1, encoding: str | None = None, errors: str | None = None, newline: str | None = None) -> IO[Any]`, which is not assignable to `Overload[
  (self: Path, mode: OpenTextMode = 'r', buffering: int = -1, encoding: str | None = None, errors: str | None = None, newline: str | None = None) -> TextIOWrapper
  (self: Path, mode: OpenBinaryMode, buffering: Literal[0], encoding: None = None, errors: None = None, newline: None = None) -> FileIO
  (self: Path, mode: OpenBinaryModeUpdating, buffering: Literal[-1, 1] = -1, encoding: None = None, errors: None = None, newline: None = None) -> BufferedRandom
  (self: Path, mode: OpenBinaryModeWriting, buffering: Literal[-1, 1] = -1, encoding: None = None, errors: None = None, newline: None = None) -> BufferedWriter
  (self: Path, mode: OpenBinaryModeReading, buffering: Literal[-1, 1] = -1, encoding: None = None, errors: None = None, newline: None = None) -> BufferedReader
  (self: Path, mode: OpenBinaryMode, buffering: int = -1, encoding: None = None, errors: None = None, newline: None = None) -> BinaryIO
  (self: Path, mode: str, buffering: int = -1, encoding: str | None = None, errors: str | None = None, newline: str | None = None) -> IO[Any]
]`, the type of `Path.open`
```

### Root Cause
`pathlib.Path.open` in Python's standard library typeshed stubs defines 7
distinct `@overload` signatures mapping specific `mode` and `buffering` values
to specific return types (`TextIOWrapper`, `BufferedReader`, `FileIO`, etc.).
`Path.open` defines a single non-overloaded implementation returning `IO[Any]`,
which is not assignable to the parent's specialized overload returns.

### Suggested Fix
Replicate the 7 `@overload` signatures under `if TYPE_CHECKING:` matching
`typeshed`:

```python
from typing import TYPE_CHECKING, Any, Optional, overload

if TYPE_CHECKING:
    import io
    from typing import BinaryIO, IO, Literal
    from _typeshed import (
        OpenBinaryMode,
        OpenBinaryModeReading,
        OpenBinaryModeUpdating,
        OpenBinaryModeWriting,
        OpenTextMode,
    )

class Path(pathlib.Path):
    if TYPE_CHECKING:
        @overload
        def open(
            self,
            mode: OpenTextMode = "r",
            buffering: int = -1,
            encoding: Optional[str] = None,
            errors: Optional[str] = None,
            newline: Optional[str] = None,
        ) -> io.TextIOWrapper: ...

        @overload
        def open(
            self,
            mode: OpenBinaryMode,
            buffering: Literal[0],
            encoding: None = None,
            errors: None = None,
            newline: None = None,
        ) -> io.FileIO: ...

        @overload
        def open(
            self,
            mode: OpenBinaryModeUpdating,
            buffering: Literal[-1, 1] = -1,
            encoding: None = None,
            errors: None = None,
            newline: None = None,
        ) -> io.BufferedRandom: ...

        @overload
        def open(
            self,
            mode: OpenBinaryModeWriting,
            buffering: Literal[-1, 1] = -1,
            encoding: None = None,
            errors: None = None,
            newline: None = None,
        ) -> io.BufferedWriter: ...

        @overload
        def open(
            self,
            mode: OpenBinaryModeReading,
            buffering: Literal[-1, 1] = -1,
            encoding: None = None,
            errors: None = None,
            newline: None = None,
        ) -> io.BufferedReader: ...

        @overload
        def open(
            self,
            mode: OpenBinaryMode,
            buffering: int = -1,
            encoding: None = None,
            errors: None = None,
            newline: None = None,
        ) -> BinaryIO: ...

        @overload
        def open(
            self,
            mode: str,
            buffering: int = -1,
            encoding: Optional[str] = None,
            errors: Optional[str] = None,
            newline: Optional[str] = None,
        ) -> IO[Any]: ...

    # override
    def open(
        self,
        mode: str = "r",
        buffering: int = -1,
        encoding: Optional[str] = None,
        errors: Optional[str] = None,
        newline: Optional[str] = None,
    ) -> Any:
        return self._as_path().open(
            mode=mode,
            buffering=buffering,
            encoding=encoding,
            errors=errors,
            newline=newline,
        )
```

---

## 2. `_BzlXrefField.make_xrefs` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:356`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:356`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L356)
* **Parent Class**: `sphinx.util.docfields.Field` (`Field.make_xrefs`)

### Error Without Suppression
```text
ERROR Class member `_BzlXrefField.make_xrefs` overrides parent class `Field` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:356:9
    |
356 |     def make_xrefs(
    |         ^^^^^^^^^^
    |
  Parameter `location` has type `Element | None`, which is not a supertype of `Node | tuple[str, int] | None`, the type in `Field.make_xrefs`
```

### Root Cause
In `sphinx.util.docfields.Field`, `location` is typed as
`Node | tuple[str, int] | None`. `_BzlXrefField.make_xrefs` narrows `location`
to `docutils_nodes.Element | None`. Narrowing parameter types violates LSP
contravariance because callers passing `(filename, lineno)` tuples or generic
`Node` instances would be rejected by the subclass.

### Suggested Fix
Widen `location` parameter type annotation to match `Field.make_xrefs`:

```python
    @override
    def make_xrefs(
        self,
        rolename: str,
        domain: str,
        target: str,
        innernode: type[sphinx_typing.TextlikeNode] = addnodes.literal_emphasis,
        contnode: typing.Union[docutils_nodes.Node, None] = None,
        env: typing.Union[environment.BuildEnvironment, None] = None,
        inliner: typing.Union[states.Inliner, None] = None,
        location: typing.Union[docutils_nodes.Node, Tuple[str, int], None] = None,
    ) -> list[docutils_nodes.Node]:
```

---

## 3. `_BzlFileDirective.run` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:517`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:517`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L517)
* **Parent Class**: `docutils.parsers.rst.Directive` (`Directive.run`) via `SphinxDirective`

### Error Without Suppression
```text
ERROR Class member `_BzlFileDirective.run` overrides parent class `Directive` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:517:9
    |
517 |     def run(self) -> list[docutils_nodes.Node]:
    |         ^^^
    |
  Return type `list[docutils_nodes.Node]` is not assignable to `list[docutils.nodes.Node]` due to `list` invariance in type stubs
```

### Root Cause
`docutils.parsers.rst.Directive.run` returns `list[docutils.nodes.Node]`.
Because `list` is invariant in Python's type system, slight module alias /
submodule import differences (e.g. `docutils.nodes.Node` vs
`docutils_nodes.Node`) or unannotated stubs cause Pyrefly to reject the return
type subtyping.

### Suggested Fix
Import `Node` directly from `docutils.nodes` or use `Sequence[docutils_nodes.Node]`:

```python
    @override
    def run(self) -> list[docutils_nodes.Node]:
        ...
```

---

## 4. `_BzlObject.before_content` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:622`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:622`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L622)
* **Parent Class**: `sphinx.directives.ObjectDescription[_BzlObjectId]` (`ObjectDescription.before_content`)

### Error Without Suppression
```text
ERROR Class member `_BzlObject.before_content` overrides parent class `ObjectDescription` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:622:9
    |
622 |     def before_content(self) -> None:
    |         ^^^^^^^^^^^^^^
```

### Root Cause
In `sphinx.directives.ObjectDescription[AstT]`, generic instantiation with
`_BzlObjectId` can cause method signature resolution inconsistencies when base
type stubs expect non-generic or differently bounded `AstT`.

### Suggested Fix
Ensure `_BzlObjectId` is a valid AST type and match `ObjectDescription.before_content`:

```python
    @override
    def before_content(self) -> None:
        ...
```

---

## 5. `_BzlObject.transform_content` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:629`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:629`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L629)
* **Parent Class**: `sphinx.directives.ObjectDescription[_BzlObjectId]` (`ObjectDescription.transform_content`)

### Error Without Suppression
```text
ERROR Class member `_BzlObject.transform_content` overrides parent class `ObjectDescription` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:629:9
    |
629 |     def transform_content(
    |         ^^^^^^^^^^^^^^^^^
    |
  Parameter name mismatch: expected `contentnode`, found `content_node`
```

### Root Cause
In `sphinx.directives.ObjectDescription`, the parameter is named `contentnode`
(without underscore). In `_BzlObject`, it was named `content_node`. Under
Python keyword argument calling rules, renaming parameters breaks LSP for
keyword callers (`obj.transform_content(contentnode=...)`).

### Suggested Fix
Rename `content_node` parameter to `contentnode`:

```python
    @override
    def transform_content(self, contentnode: addnodes.desc_content) -> None:
        ...
```

---

## 6. `_BzlObject.after_content` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:687`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:687`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L687)
* **Parent Class**: `sphinx.directives.ObjectDescription[_BzlObjectId]` (`ObjectDescription.after_content`)

### Error Without Suppression
```text
ERROR Class member `_BzlObject.after_content` overrides parent class `ObjectDescription` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:687:9
    |
687 |     def after_content(self) -> None:
    |         ^^^^^^^^^^^^^
```

### Root Cause
Generic type parameter resolution on `ObjectDescription[_BzlObjectId]` method
table.

### Suggested Fix
Match `ObjectDescription.after_content`:

```python
    @override
    def after_content(self) -> None:
        ...
```

---

## 7. `_BzlObject.handle_signature` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:695`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:695`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L695)
* **Parent Class**: `sphinx.directives.ObjectDescription[_BzlObjectId]` (`ObjectDescription.handle_signature`)

### Error Without Suppression
```text
ERROR Class member `_BzlObject.handle_signature` overrides parent class `ObjectDescription` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:695:9
    |
695 |     def handle_signature(
    |         ^^^^^^^^^^^^^^^^
    |
  Parameter name mismatch: expected `signode`, found `sig_node`
```

### Root Cause
The base method in `sphinx.directives.ObjectDescription` has signature
`handle_signature(self, sig: str, signode: desc_signature) -> AstT`.
`_BzlObject` named the parameter `sig_node` instead of `signode`.

### Suggested Fix
Rename `sig_node` to `signode` and retain `-> _BzlObjectId` return type:

```python
    @override
    def handle_signature(
        self, sig: str, signode: addnodes.desc_signature
    ) -> _BzlObjectId:
        ...
```

---

## 8. `_BzlObject.add_target_and_index` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:803`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:803`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L803)
* **Parent Class**: `sphinx.directives.ObjectDescription[_BzlObjectId]` (`ObjectDescription.add_target_and_index`)

### Error Without Suppression
```text
ERROR Class member `_BzlObject.add_target_and_index` overrides parent class `ObjectDescription` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:803:9
    |
803 |     def add_target_and_index(
    |         ^^^^^^^^^^^^^^^^^^^^
    |
  Parameter name mismatch: expected `signode`, found `sig_node`
```

### Root Cause
In `sphinx.directives.ObjectDescription`, the base signature is
`add_target_and_index(self, name: AstT, sig: str, signode: desc_signature) -> None`.
`_BzlObject` named the parameter `sig_node` instead of `signode`.

### Suggested Fix
Rename parameter `sig_node` to `signode`:

```python
    @override
    def add_target_and_index(
        self,
        name: _BzlObjectId,
        sig: str,
        signode: addnodes.desc_signature,
    ) -> None:
        ...
```

---

## 9. `_BzlObject._object_hierarchy_parts` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:872`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:872`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L872)
* **Parent Class**: `sphinx.directives.ObjectDescription[_BzlObjectId]` (`ObjectDescription._object_hierarchy_parts`)

### Error Without Suppression
```text
ERROR Class member `_BzlObject._object_hierarchy_parts` overrides parent class `ObjectDescription` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:872:9
    |
872 |     def _object_hierarchy_parts(
    |         ^^^^^^^^^^^^^^^^^^^^^^^
    |
  Parameter name mismatch: expected `sig_node` vs `signode` depending on Sphinx version
```

### Root Cause
In Sphinx 7/8 stubs, `_object_hierarchy_parts` accepts `(self, sig_node: desc_signature) -> tuple[str, ...]`.
Parameter name differences or return type tuple invariance triggers Pyrefly's
override checker.

### Suggested Fix
Align signature with `ObjectDescription._object_hierarchy_parts`:

```python
    @override
    def _object_hierarchy_parts(
        self, sig_node: addnodes.desc_signature
    ) -> tuple[str, ...]:
        ...
```

---

## 10. `_BzlObject._toc_entry_name` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:878`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:878`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L878)
* **Parent Class**: `sphinx.directives.ObjectDescription[_BzlObjectId]` (`ObjectDescription._toc_entry_name`)

### Error Without Suppression
```text
ERROR Class member `_BzlObject._toc_entry_name` overrides parent class `ObjectDescription` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:878:9
    |
878 |     def _toc_entry_name(
    |         ^^^^^^^^^^^^^^^
```

### Root Cause
In Sphinx base class, `_toc_entry_name(self, sig_node: desc_signature) -> str`.
Parameter naming or AST generic type propagation difference causes override
inconsistency.

### Suggested Fix
Align signature with `ObjectDescription._toc_entry_name`:

```python
    @override
    def _toc_entry_name(self, sig_node: addnodes.desc_signature) -> str:
        ...
```

---

## 11. `_BzlDomain.get_full_qualified_name` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1642`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1642`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L1642)
* **Parent Class**: `sphinx.domains.Domain` (`Domain.get_full_qualified_name`)

### Error Without Suppression
```text
ERROR Class member `_BzlDomain.get_full_qualified_name` overrides parent class `Domain` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1642:9
    |
1642 |     def get_full_qualified_name(
     |         ^^^^^^^^^^^^^^^^^^^^^^^
    |
  Parameter `node` has type `docutils_nodes.Element`, which is not a supertype of `docutils.nodes.Element`
```

### Root Cause
In `sphinx.domains.Domain`, `get_full_qualified_name(self, node: Element) -> str | None`.
`docutils_nodes.Element` alias vs `docutils.nodes.Element` typeshed stubs creates
a type mismatch if stubs are incomplete.

### Suggested Fix
Align parameter type with `sphinx.domains.Domain`:

```python
    @override
    def get_full_qualified_name(
        self, node: docutils_nodes.Element
    ) -> typing.Union[str, None]:
        ...
```

---

## 12. `_BzlDomain.get_objects` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1651`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1651`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L1651)
* **Parent Class**: `sphinx.domains.Domain` (`Domain.get_objects`)

### Error Without Suppression
```text
ERROR Class member `_BzlDomain.get_objects` overrides parent class `Domain` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1651:9
    |
1651 |     def get_objects(self) -> Iterable[_GetObjectsTuple]:
     |         ^^^^^^^^^^^
    |
  Return type `Iterable[_GetObjectsTuple]` is not assignable to `Iterable[tuple[str, str, str, str, str, int]]`
```

### Root Cause
`sphinx.domains.Domain.get_objects` returns
`Iterable[tuple[str, str, str, str, str, int]]`.
`_GetObjectsTuple` in `bzl.py` must be defined as a `NamedTuple` subclassing
the exact 6-tuple shape so that it is recognized as a subtype of
`tuple[str, str, str, str, str, int]`.

### Suggested Fix
Define `_GetObjectsTuple` as a `NamedTuple` and annotate `get_objects`:

```python
class _GetObjectsTuple(typing.NamedTuple):
    name: str
    dispname: str
    object_type: str
    docname: str
    anchor: str
    priority: int

class _BzlDomain(domains.Domain):
    @override
    def get_objects(self) -> Iterable[_GetObjectsTuple]:
        ...
```

---

## 13. `_BzlDomain.resolve_any_xref` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1657`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1657`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L1657)
* **Parent Class**: `sphinx.domains.Domain` (`Domain.resolve_any_xref`)

### Error Without Suppression
```text
ERROR Class member `_BzlDomain.resolve_any_xref` overrides parent class `Domain` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1657:9
    |
1657 |     def resolve_any_xref(
     |         ^^^^^^^^^^^^^^^^
```

### Root Cause
In `sphinx.domains.Domain`, `resolve_any_xref` signature is:
`resolve_any_xref(self, env: BuildEnvironment, fromdocname: str, builder: Builder, target: str, node: pending_xref, contnode: Element) -> list[tuple[str, Element]]`.
Differences in `contnode` type or tuple return type structure trigger `bad-override`.

### Suggested Fix
Match parameter and return types:

```python
    @override
    def resolve_any_xref(
        self,
        env: environment.BuildEnvironment,
        fromdocname: str,
        builder: builders.Builder,
        target: str,
        node: addnodes.pending_xref,
        contnode: docutils_nodes.Element,
    ) -> list[tuple[str, docutils_nodes.Element]]:
        ...
```

---

## 14. `_BzlDomain.resolve_xref` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1680`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1680`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L1680)
* **Parent Class**: `sphinx.domains.Domain` (`Domain.resolve_xref`)

### Error Without Suppression
```text
ERROR Class member `_BzlDomain.resolve_xref` overrides parent class `Domain` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1680:9
    |
1680 |     def resolve_xref(
     |         ^^^^^^^^^^^^
```

### Root Cause
In `sphinx.domains.Domain`, `resolve_xref` signature is:
`resolve_xref(self, env: BuildEnvironment, fromdocname: str, builder: Builder, typ: str, target: str, node: pending_xref, contnode: Element) -> Element | None`.
Type alias differences on `contnode: docutils_nodes.Element` vs `nodes.Element`
trigger `bad-override`.

### Suggested Fix
Match parameter and return types with `Domain.resolve_xref`:

```python
    @override
    def resolve_xref(
        self,
        env: environment.BuildEnvironment,
        fromdocname: str,
        builder: builders.Builder,
        typ: str,
        target: str,
        node: addnodes.pending_xref,
        contnode: docutils_nodes.Element,
    ) -> typing.Union[docutils_nodes.Element, None]:
        ...
```

---

## 15. `_BzlDomain.clear_doc` (`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1790`)

* **File Location**: [`sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1790`](file:///usr/local/google/home/rlevasseur/.gemini/jetski/worktrees/rules_python/enable_pyrefly_python_targets/sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py#L1790)
* **Parent Class**: `sphinx.domains.Domain` (`Domain.clear_doc`)

### Error Without Suppression
```text
ERROR Class member `_BzlDomain.clear_doc` overrides parent class `Domain` in an inconsistent manner [bad-override]
   --> sphinxdocs/sphinxdocs/src/sphinx_bzl/bzl.py:1790:9
    |
1790 |     def clear_doc(self, docname: str) -> None:
     |         ^^^^^^^^^
```

### Root Cause
In `sphinx.domains.Domain`, `clear_doc(self, docname: str) -> None`.
If base domain methods in Sphinx stubs are unannotated or differ across
Sphinx versions, Pyrefly flags the override.

### Suggested Fix
Match signature with `Domain.clear_doc`:

```python
    @override
    def clear_doc(self, docname: str) -> None:
        ...
```
