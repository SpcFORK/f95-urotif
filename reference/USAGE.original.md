
# Urotif Language Documentation

## Overview

Urotif is a stack-based, esoteric programming language implemented in Oak. It features a unique syntax where most operations work with a stack data structure, and supports various data types including numbers, strings, arrays, and objects.

## Getting Started

### Running Urotif Programs

There are several ways to run Urotif code:

#### 1. Using the REPL (Interactive Mode)
```bash
oak urotif/repl.oak
```
This starts an interactive session where you can type Urotif commands and see immediate results.

#### 2. Running a File
```bash
oak urotif/run.oak <filename>
```
Example:
```bash
oak urotif/run.oak smp/hello.utf
```

#### 3. Running Code Directly
```bash
oak urotif/single.oak "<urotif_code>"
```
Example:
```bash
oak urotif/single.oak "[Hello, World\!]P@"
```

#### 4. Using Compiled Executables
After building with `./fmt.sh`, you can use the compiled versions:
```bash
./out/run smp/hello.utf
./out/single "[Hello, World\!]P@"
./out/repl
```

### File Extensions

Urotif programs typically use these extensions:
- `.utf` - Standard Urotif files
- `.uru` - Urotif rule files
- `.urb` - Urotif binary/bytecode files

## Language Syntax

### Program Structure

Every Urotif program should start with:
```urotif
=) urotif
```
This indicates the start of a Urotif program and sets the execution pointer to line 1.

### Basic Operations

#### Stack Operations
- `_` - Pop (remove top item from stack)
- `%` - Duplicate top item (peek and push)
- `$` - Print top item and pop it

#### Arithmetic
- `+` - Add two numbers
- `-` - Subtract (second from top minus top)
- `*` - Multiply two numbers
- `|` - Divide (second from top divided by top)
- `~` - Negate top number

#### Data Input
- `` ` `` - Read input from user and push to stack

#### Arrays and Objects
- `[` - Start array creation
- `]` - End array creation and push to stack
- `{` - Start number creation (digits)
- `}` - End number creation and convert to number

#### String Literals
Characters and strings can be pushed directly:
- Letters, numbers, and basic symbols push themselves
- `\n` - Newline character
- `\"` - Quote character
- `\'` - Apostrophe character

#### Advanced Operations (@-commands)

The `@` operator performs advanced operations based on the top stack item:

##### Printing
- `'p'@` - Print array/string elements
- `'P'@` - Print array/string elements with newline

##### String Operations
- `'s'@` - Convert to string
- `'S'@` - Join array elements into string

##### Evaluation
- `'e'@` - Evaluate code
- `'E'@` - Evaluate code and push result

##### Array Operations
- `'i'@` - Reverse array
- `'g'@` - Get property from object

##### File Operations
- `'u'@` - Read and evaluate file
- `'i'@` - Import module

##### Control Flow
- `'*'@` - Get/set variable
- `'v'@` - Get variable value
- `'V'@` - Set variable value

### Control Flow

#### Conditional Execution
- `=` - Compare top two items, if equal, jump to coordinates
- `^` - Unconditional jump to coordinates (y, x from stack)

#### Comments
- `#` - Move to next line (comment rest of line)

### Examples

#### Hello World
```urotif
=) urotif
[Hello, World\!]P@
```

#### Simple Calculator
```urotif
=) urotif
`{123}+$
```
This reads input, adds 123 to it, and prints the result.

#### Fibonacci Sequence
```urotif
=) urotif
{0}{1}
{10}[
  %$
  %{2}[-+
]{1}-
```

## Data Types

### Numbers
- Integers: `{123}`
- Floats: `{3.14}`

### Strings
- Character sequences: `Hello`
- Escaped characters: `\n`, `\"`, `\'`

### Arrays
- `[item1, item2, item3]`
- Arrays can contain mixed data types

### Objects
- Created using `&` with key-value pairs
- Accessed using `'g'@` command

## Memory Model

Urotif uses a stack-based memory model with:
- **Main Stack**: Primary data storage
- **Memory Stack**: For nested operations and array/object creation
- **Tables**: For variable storage and lookup

## Error Handling

- Division by zero results in infinity
- Invalid operations may silently fail or produce unexpected results
- File operations return null on failure

## Best Practices

1. **Start with `=) urotif`**: Always begin programs with this header
2. **Use descriptive comments**: Use `#` to add line comments
3. **Test incrementally**: Use the REPL to test code snippets
4. **Manage stack carefully**: Keep track of stack depth to avoid errors
5. **Use arrays for complex data**: Group related data in arrays

## Common Patterns

### Input/Output
```urotif
` $          # Read input and print it
[Enter: ]P@` [You entered: ]P@$
```

### Loops
```urotif
{10}[        # Loop 10 times
  # loop body
]{1}-
```

### Conditionals
```urotif
`{5}={2}{1}^ # If input equals 5, jump to line 2, char 1
```

## Debugging

Use the REPL to:
- Test individual operations
- Check stack state with `%$` (duplicate and print)
- Verify data types and values
- Step through complex operations

## File Organization

- Keep main logic in `.utf` files
- Use descriptive filenames
- Group related functionality
- Comment complex operations

This documentation provides the foundation for working with Urotif. For more advanced features and edge cases, experiment with the REPL and examine the example files in the `smp/` directory.
