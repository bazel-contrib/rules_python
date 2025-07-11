from ...my_library import (
    some_function,
)  # Import path should be package1.my_library.some_function
from ...my_library.foo import (  # Import path should be package1.my_library.foo.some_function
    some_function,
)
from .. import some_function  # Import path should be package1.subpackage1.some_function
from .. import some_module  # Import path should be package1.subpackage1.some_module
from .library import (  # Import path should be package1.subpackage1.subpackage2.library.other_module
    other_module,
)
