"""A small library to check which lines are reported as covered."""


def covered(value):
    if value:
        return "truthy"
    return "falsy"


def not_covered():
    return "never called"
