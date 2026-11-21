"""A small library to check which lines are reported as covered.

The lines are looked up by their content in the tests, so keep them unique.
"""


def covered(value):
    if value:
        return "truthy"
    return "falsy"


def not_covered():
    return "never called"


def excluded_by_coveragerc():
    return "excluded by coveragerc"


def excluded_by_base_coveragerc():
    return "excluded by base coveragerc"


class Greeter:
    def greet(self, name):
        return "hello " + name

    def unused(self):
        return "unused method"
