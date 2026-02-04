# V Language (0.5.x) Skill Guide

**Version**: 0.5.x (Stable/Weekly 2026+)
**Website**: https://vlang.io
**Repository**: https://github.com/vlang/v

## 1. Core Concepts
V is a statically typed, compiled language emphasizing simplicity, performance, and safety.
- **No Null**: Pointers are non-null by default. Use `Option` types for nullable values.
- **No Global Variables**: (By default).
- **Immutability**: Variables are immutable by default (`mut` required).
- **Pure Functions**: (By default).
- **Compilation**: Transpiles to C (default) or native code.

## 2. Syntax Basics

### Variables
```v
fn main() {
    name := 'Bob'          // Type inferred (string)
    mut age := 20          // Mutable
    age = 21

    // Large numbers
    large := 1_000_000
}
```

### Functions
```v
fn add(x int, y int) int {
    return x + y
}

// Multiple returns
fn split_name(full string) (string, string) {
    parts := full.split(' ')
    return parts[0], parts[1]
}

// Named arguments (structs only, see below)
```

### Structs
```v
struct User {
    name string
    age  int
mut:
    is_active bool // Mutable fields
pub:
    id int         // Public fields (modules)
pub mut:
    score int      // Public and mutable
}

// Initialization
u := User{
    name: 'Alice'
    age: 30
    is_active: true
}
```

### Arrays & Maps
```v
// Arrays
mut nums := [1, 2, 3]
nums << 4             // Append
println(nums.len)
println(nums[1..3])   // Slicing

// Fixed arrays
arr := [10]int{}

// Maps
mut scores := map[string]int{}
scores['alice'] = 100
val := scores['bob'] or { 0 } // Handle missing key
```

## 3. Control Flow

### Loop (Only `for`)
```v
// "While" loop
mut sum := 0
for sum < 100 {
    sum++
}

// Range
for i in 0..5 {
    println(i) // 0, 1, 2, 3, 4
}

// Array iteration
names := ['a', 'b', 'c']
for i, name in names {
    println('$i: $name')
}

// Map iteration
for key, val in scores {
    println('$key -> $val')
}
```

### Match (Switch)
```v
os := 'linux'
match os {
    'windows' { println('Win') }
    'linux'   { println('Tux') }
    else      { println('Unknown') }
}
```

## 4. Type System & Error Handling

### Option Types (`?T`)
Used for values that might be `none`.
```v
fn find_user(id int) ?User {
    if id == 0 {
        return none
    }
    return User{name: 'Found'}
}

// Handling
u := find_user(1) or {
    println('Not found')
    return
}
// u is now User (unwrapped)
```

### Result Types (`!T`)
Used for operations that can fail with an error.
```v
fn read_file(path string) !string {
    if path == '' {
        return error('empty path')
    }
    return 'content'
}

// Handling
content := read_file('file.txt') or {
    panic(err)
}
```

### Sum Types
```v
struct Cat { name string }
struct Dog { breed string }

type Pet = Cat | Dog

fn greet(p Pet) {
    match p {
        Cat { println('Meow ${p.name}') }
        Dog { println('Woof ${p.breed}') }
    }
}
```

### Generics
```v
fn print_val[T](val T) {
    println(val)
}

struct Container[T] {
    item T
}
```

## 5. Memory Management
V uses Autofree (compile-time memory management) by default in production.
- **References**: Use `&` to pass by reference (avoid copy).
- **Heap**: Use `[heap]` attribute on structs if they must be on the heap (rarely needed explicitly unless large).

```v
fn update_user(mut u User) {
    u.age++
}

fn main() {
    mut user := User{name: 'Test'}
    update_user(mut user) // Pass with `mut`
}
```

## 6. Concurrency
Based on CSP (Communicating Sequential Processes).

### Spawning
```v
fn worker(id int) {
    println('Worker $id')
}

fn main() {
    for i in 0..5 {
        spawn worker(i)
    }
    // Main thread exits immediately, normally wait using channels or sync
}
```

### Channels
```v
ch := chan int{cap: 10}
spawn fn(c chan int) {
    c <- 100
}(ch)

val := <-ch
```

### Shared Objects
```v
struct St {
    x int
}

fn main() {
    shared s := St{} 
    spawn fn(shared s St) {
        lock s {
            s.x++
        }
    }(shared s)
    
    rlock s {
        println(s.x)
    }
}
```

## 7. 0.5.x Specific Features & Changes
- **Defer Scoping**: `defer {}` is now block-scoped (runs at end of block), not function-scoped. Use `defer(fn){}` for old behavior.
- **Comptime**: New `if is shared` and `v.comptime` stage.
- **Graphics**: `gx` module deprecated -> use `gg`.
- **JSON**: New `json2` implementation (faster).
- **Web**: Multithreaded `veb` backend available (`-d new_veb`).

## 8. Standard Library Highlights
- `os`: File system, args, env (`os.read_file`, `os.args`).
- `json`: `json.decode(Type, string)!`, `json.encode(val)`.
- `net.http`: `http.get`, `http.post`.
- `math`: Standard math functions.
- `flag`: CLI argument parsing.

## 9. Project Structure
- **v.mod**: Project metadata (TOML format).
- **Modules**: Folders define modules.
  ```text
  /myproject
    v.mod
    main.v      (module main)
    /utils
      helper.v  (module utils)
  ```
- **Import**: `import utils` (if in same root) or `import os`.

## 10. Best Practices
- Use `v fmt -w .` to format code.
- Prefer `Option` (`?T`) for "not found" logic.
- Prefer `Result` (`!T`) for errors.
- Use `mut` only when necessary.
- Snake_case for functions/vars, PascalCase for Structs.
- Test files end in `_test.v`, run with `v test .`.
