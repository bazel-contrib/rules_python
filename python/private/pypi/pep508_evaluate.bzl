# Copyright 2025 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Parsing and evaluation of the environment markers.

See https://packaging.python.org/en/latest/specifications/dependency-specifiers/#environment-markers
"""

load("//python/private:version.bzl", "version")

# The variables that can be used in the markers. The values tell if the
# variable is compared as a version if the other side of the expression is a
# valid version specifier.
_VARIABLES = {
    "dependency_groups": False,
    "extra": False,
    "extras": False,
    "implementation_name": False,
    "implementation_version": True,
    "os_name": False,
    "platform_machine": False,
    "platform_python_implementation": False,
    "platform_release": True,
    "platform_system": False,
    "platform_version": False,
    "python_full_version": True,
    "python_version": True,
    "sys_platform": False,
}

# The deprecated names that are still found in the metadata of old packages.
_VARIABLE_ALIASES = {
    "os.name": "os_name",
    "platform.machine": "platform_machine",
    "platform.python_implementation": "platform_python_implementation",
    "platform.version": "platform_version",
    "python_implementation": "platform_python_implementation",
    "sys.platform": "sys_platform",
}

_VERSION_OPERATORS = {
    "!=": version.is_ne,
    "<": version.is_lt,
    "<=": version.is_le,
    "==": version.is_eq,
    ">": version.is_gt,
    ">=": version.is_ge,
    "~=": version.is_compatible,
}
_OPERATORS = ["!=", "<", "<=", "==", "===", ">", ">=", "in", "not in", "~="]
_OPERATOR_CHARS = "<>!=~"
_AND = "and"
_OR = "or"

# The key of the `env` that has the functions to normalize the strings that
# the variables are compared with, e.g. `{"platform_machine": lambda x: ...}`.
# The variables that are compared as versions cannot be normalized.
_ENV_ALIASES = "_aliases"

def tokenize(marker):
    """Tokenize the marker, this is only exposed for the tests.

    Args:
        marker: {type}`str` The marker to tokenize.

    Returns:
        {type}`list[str]` The tokens without whitespace. The strings are quoted
        with `"` unless they contain it.
    """
    tokens, err = _tokenize(marker)
    if err:
        fail(_error(err, marker))

    return tokens

def _error(err, marker):
    return "{} in the marker: {}".format(err, marker)

def _tokenize(marker):
    """Tokenize the marker.

    Returns:
        A tuple of the list of tokens and an error message, where one of them is None.
    """
    if "\n" in marker or "\r" in marker:
        return None, "Unexpected line break"

    tokens = []
    rest = marker

    # Anything can be in the strings, so find them and tokenize what is
    # between them. Each iteration handles one string, which is at least 2 chars.
    for _ in range(len(marker) // 2 + 1):
        double = rest.find('"')
        single = rest.find("'")
        if double < 0 and single < 0:
            break

        if single < 0 or (double >= 0 and double < single):
            start, quote = double, '"'
        else:
            start, quote = single, "'"

        end = rest.find(quote, start + 1)
        if end < 0:
            return None, "Unterminated string"

        err = _tokenize_unquoted(rest[:start], tokens)
        if err:
            return None, err

        tokens.append(_quote(rest[start + 1:end]))
        rest = rest[end + 1:]

    err = _tokenize_unquoted(rest, tokens)
    if err:
        return None, err

    return tokens, None

def _quote(value):
    return "'{}'".format(value) if '"' in value else '"{}"'.format(value)

def _tokenize_unquoted(text, tokens):
    """Tokenize the text that does not have strings.

    Args:
        text: {type}`str` The text to tokenize.
        tokens: {type}`list[str]` The list to append the tokens to.

    Returns:
        {type}`str | None` the error message if the text is invalid.
    """
    for word in text.replace("(", " ( ").replace(")", " ) ").replace("\t", " ").split(" "):
        if not word:
            continue
        elif word == "in" and tokens and tokens[-1] == "not":
            tokens[-1] = "not in"
        elif word in ["(", ")"] or not word.strip(_OPERATOR_CHARS) or _is_name(word):
            tokens.append(word)
        else:
            # There is no whitespace between the variable and the operator,
            # e.g. `os_name==` or `<=python_version`.
            name = word.strip(_OPERATOR_CHARS)
            if not _is_name(name):
                return "Cannot parse '{}'".format(word)

            before, _, after = word.partition(name)
            tokens.extend([token for token in [before, name, after] if token])

    return None

def _is_name(word):
    return word[0].isalnum() and word.replace("_", "").replace(".", "").isalnum()

def parse(marker):
    """Parse the marker, so that it can be evaluated many times.

    Use this if the same marker is evaluated for many environments, because
    parsing the marker takes about as long as evaluating it.

    Args:
        marker: {type}`str` The marker to parse.

    Returns:
        An opaque value that can be passed to {obj}`evaluate` instead of the marker.
    """
    parsed, err = _parse(marker)
    if err:
        fail(_error(err, marker))

    return parsed

def _parse(marker):
    """Parse the marker.

    Returns:
        A tuple of the parsed marker and an error message, where one of them
        is None. The parsed marker is the list of tokens, where each
        `<variable> <operator> <string>` expression is replaced with the
        struct that is returned by `_parse_expr`.
    """
    tokens, err = _tokenize(marker)
    if err:
        return None, err

    parsed = []
    depth = 0
    want_operand = True
    skip = 0
    for i, token in enumerate(tokens):
        if skip:
            skip -= 1
            continue
        elif not want_operand:
            if token == ")":
                depth -= 1
            elif token in [_AND, _OR]:
                want_operand = True
            else:
                return None, "Expected 'and', 'or' or ')', but got '{}'".format(token)
        elif token == "(":
            depth += 1
        else:
            token, err = _parse_expr(tokens[i:i + 3])
            if err:
                return None, err
            skip = 2
            want_operand = False

        if depth < 0:
            return None, "Unbalanced ')'"
        parsed.append(token)

    if tokens and want_operand:
        return None, "Unexpected end"
    if depth:
        return None, "Unbalanced '('"

    return parsed, None

def _parse_expr(tokens):
    """Parse `<variable> <operator> <string>` or `<string> <operator> <variable>`.

    The grammar also allows comparing two variables or two strings, but
    nothing needs that and `packaging` does not evaluate those correctly, so
    they are not supported.

    Returns:
        A tuple of the parsed expression and an error message, where one of
        them is None.
    """
    if len(tokens) != 3 or tokens[1] not in _OPERATORS:
        return None, "Expected '<variable> <operator> <string>' at '{}'".format(" ".join(tokens))

    left, op, right = tokens
    value_is_left = left[0] in "\"'"
    if value_is_left == (right[0] in "\"'"):
        return None, "Expected a variable and a quoted string at '{}'".format(" ".join(tokens))

    name, value = (right, left[1:-1]) if value_is_left else (left, right[1:-1])
    name = _VARIABLE_ALIASES.get(name, name)
    if name not in _VARIABLES:
        return None, "Unknown variable '{}'".format(name)

    is_version = _VARIABLES[name]
    return struct(
        name = name,
        op = op,
        value = value,
        value_is_left = value_is_left,
        is_version = is_version,
        # The variable is the specifier if the value is on the left.
        specifier = _specifier(op, value) if is_version and not value_is_left else None,
        # For returning the expressions that cannot be evaluated.
        string = " ".join(tokens),
    ), None

def evaluate(marker, *, env, strict = True, _fail = fail):
    """Evaluate the marker against a given env.

    Args:
        marker: {type}`str` The marker to evaluate or the value returned by
            {obj}`parse`.
        env: {type}`dict[str, str]` The values of the variables. If it has
            the `_aliases` key, then its value is a dict of functions to
            normalize the strings that the variables are compared with, which
            is how e.g. `platform_machine == "arm64"` is true for `aarch64`.
        strict: {type}`bool` Whether to fail if a variable is not in the
            `env`. If it is `False`, then the expressions with such variables
            are not evaluated.
        _fail: Used for tests

    Returns:
        {type}`bool | str` Whether the marker is compatible with the `env`. If
        `strict` is `False` and the result depends on the variables that are
        not in the `env`, then the marker with only those variables is
        returned.
    """
    if type(marker) == "string":
        parsed, err = _parse(marker)
        if err:
            return _fail(_error(err, marker))
    else:
        parsed = marker

    # Starlark does not have recursion, hence there is a stack with a frame
    # for each open parenthesis. Because `and` binds tighter than `or`, a
    # frame is:
    # * The value of the `or` operands that we have seen so far.
    # * The value of the `and` operands that we have seen since the last `or`.
    frame = [False, True]
    stack = [frame]
    for token in parsed:
        if token == _AND:
            continue
        elif type(token) == "struct":
            value = _evaluate_expr(token, env, strict, _fail)
        elif token == _OR:
            frame[0] = _or(frame[0], frame[1])
            frame[1] = True
            continue
        elif token == "(":
            frame = [False, True]
            stack.append(frame)
            continue
        else:  # token == ")"
            stack.pop()
            value = _or(frame[0], frame[1])
            if type(value) == "string":
                value = "({})".format(value)
            frame = stack[-1]

        frame[1] = _and(frame[1], value)

    return _or(frame[0], frame[1])

# The operands of `_and` and `_or` are either bools or strings, which are the
# expressions that could not be evaluated because `strict = False`.

def _and(x, y):
    if x == False or y == False:
        return False
    elif x == True:
        return y
    elif y == True:
        return x
    else:
        return "{} and {}".format(x, y)

def _or(x, y):
    if x == True or y == True:
        return True
    elif x == False:
        return y
    elif y == False:
        return x
    else:
        return "{} or {}".format(x, y)

def _evaluate_expr(expr, env, strict, _fail):
    """Evaluate the expression that is returned by `_parse_expr`.

    Returns:
        {type}`bool | str` the result or the expression itself if the variable
        is not in the `env` and `strict` is `False`.
    """
    if expr.name not in env:
        if not strict:
            return expr.string

        return _fail("The variable '{}' is not in the environment, cannot evaluate: {}".format(
            expr.name,
            expr.string,
        ))

    env_value = env[expr.name]
    if expr.is_version:
        if expr.value_is_left:
            return _version_expr(expr.value, expr.op, env_value, _specifier(expr.op, env_value), _fail)
        else:
            return _version_expr(env_value, expr.op, expr.value, expr.specifier, _fail)

    value = expr.value
    normalize = env.get(_ENV_ALIASES, {}).get(expr.name)
    if normalize:
        value = normalize(value)

    if expr.value_is_left:
        return _string_expr(value, expr.op, env_value, _fail)
    else:
        return _string_expr(env_value, expr.op, value, _fail)

def _string_expr(left, op, right, _fail):
    """Evaluate a string comparison expression"""
    if op == "==":
        return left == right
    elif op == "!=":
        return left != right
    elif op == "in":
        return left in right
    elif op == "not in":
        return left not in right
    elif op in ["<", ">"]:
        # The ordered comparison is only defined for versions, which means
        # that only the equality can be checked.
        return False
    elif op in ["<=", ">="]:
        return left == right
    else:
        return _fail("The operator '{}' can only be used with versions: '{}' {} '{}'".format(op, left, op, right))

def _specifier(op, value):
    """Parse the version of the `<op><value>` version specifier.

    Returns:
        `None` if it is not a valid version specifier. Otherwise the string to
        compare with for `===` and the parsed version for the other operators.
    """
    if op == "===":
        # The arbitrary equality accepts anything that can be in a list of
        # specifiers, see
        # https://packaging.python.org/en/latest/specifications/version-specifiers/#arbitrary-equality
        value = value.strip().lower()
        return None if [c for c in " \t\n;)".elems() if c in value] else value
    elif op not in _VERSION_OPERATORS:
        return None

    spec = version.parse(value)
    if spec == None:
        return None
    elif op in ["==", "!="]:
        return spec
    elif spec.is_prefix or spec.local:
        # Only the equality can be used with prefix matching or local versions.
        return None
    elif op == "~=" and len(spec.release) < 2:
        return None
    else:
        return spec

def _version_expr(left, op, right, specifier, _fail):
    """Evaluate a version comparison expression.

    Args:
        left: {type}`str` The version to check.
        op: {type}`str` The operator.
        right: {type}`str` The version of the specifier.
        specifier: The result of `_specifier(op, right)`.
        _fail: The function to report the errors with.

    Returns:
        {type}`bool`
    """
    if specifier == None:
        # Per spec, if it is not a valid version specifier, then fallback to
        # the string comparison.
        return _string_expr(left, op, right, _fail)
    elif op == "===":
        return left.strip().lower() == specifier

    candidate = version.parse(left)
    if candidate == None or candidate.is_prefix:
        # Something that is not a version cannot match a version specifier.
        return False

    return _VERSION_OPERATORS[op](candidate, specifier)
