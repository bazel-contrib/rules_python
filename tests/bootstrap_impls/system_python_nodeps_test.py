print("Hello, world")

# Verify py code from the stdlib can be imported.
import pathlib

print(pathlib)

# Verify a C-implemented module can be imported.
# Socket isn't implement in C, but requires `_socket`,
# which is implemented in C
import socket
