# Search Open Finder Windows — Alfred Workflow v2.1.1

## Version 2.1.1 - Change Log

### Features

- Refinements to icons
- Now uses macOS' built-in "Network" icon
- Improved handling of nonstandard windows when Finder is not in focus

### Performance

- Consolidated string matching blocks
- Replaced regular expression matching with zsh-optimized `case` statements and glob patterns
- Implemented more concise, zsh-native parameter expansion
- Explicitly defined remaining executables with their paths to eliminate `$PATH` lookup

### Codebase

- Replaced unnecessary associative arrays with regular arrays

### Bug fixes

- Resolves an issue where the displayed name of the **iCloud Drive** folder would appear incorrectly
- Resolves a rare issue that would cause the script filter to hang if a "Get Info" window's inspected item does not have a real UNIX path