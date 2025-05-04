# Getting a REPL or Interactive Shell

rules_python provides a REPL to help with debugging and developing. The goal of
the REPL is to present an environment identical to what a `py_binary` creates
for your code.

## Usage



## Customizing the shell

By default, the `//python/bin:repl` target will invoke the shell from the `code`
module. It's possible to switch to another shell by writing a custom "stub" and
pointing the target at the necessary dependencies.

For an IPython shell, create a file as follows.

```python
import IPython
IPython.start_ipython()
```

Assuming the file is called `ipython_stub.py` and the `pip.parse` hub's name is
`my_deps`, then set this up in the .bazelrc file:
```
# Allow the REPL stub to import ipython. In this case, @my_deps is the hub name
# of the pip.parse() call.
build --@rules_python//python/bin:repl_stub_dep=@my_deps//ipython

# Point the REPL at the stub created above.
build --@rules_python//python/bin:repl_stub=//path/to:ipython_stub.py
```
