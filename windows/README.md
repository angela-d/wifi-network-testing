The `windows` directory exists so we can import dependencies without requiring the user to install applications they don't really need.

Applications in this directory are called in an environment variable, so they behave as if they are installed:
```
ADDL_EXE=./windows/bind9:./windows/bc
export PATH=$ADDL_EXE:$PATH
```

For any new dependencies added, you can simply append the path, prefixed by the ':' separator.
