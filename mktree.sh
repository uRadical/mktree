#!/bin/bash

# mktree - Create a directory tree from a text representation
# Usage: mktree <file> or mktree -s "<tree string>"

set -e   # Exit on error
set -u   # Exit on undefined variable

# Global verbose flag
VERBOSE=false

function print_help() {
    cat <<EOF
Usage: mktree <file>
       mktree -s <string>

Creates directories and files based on the tree structure in the input file or string,
preserving the directory hierarchy while ignoring the root directory.

Options:
  -s, --string    Parse a string instead of a file
  -h, --help      Show this help message
  -v, --verbose   Show verbose output

Example:
  mktree tree.txt
  mktree -s "$(cat tree.txt)"
EOF
}

function log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        printf "DEBUG: %s\n" "$1" >&2
    fi
}

function error_exit() {
    printf "ERROR: %s\n" "$1" >&2
    exit 1
}

# Function to handle cleanup on exit or interrupt
function cleanup() {
    # Add any cleanup code here if needed
    :
}

function process_tree() {
    # First, collect all lines, ignoring empty lines
    local -a all_lines=()
    local line_count=0
    
    while IFS= read -r line; do
        # Skip empty lines
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi
        
        all_lines+=("$line")
        ((line_count++))
    done
    
    log_debug "Read $line_count lines"
    
    # Skip root directory line if it exists
    local start_index=0
    if [[ ${#all_lines[@]} -gt 0 ]]; then
        local first_line="${all_lines[0]}"
        # If first line ends with / and doesn't contain tree characters, it's a root dir
        if [[ "$first_line" =~ /$ && ! "$first_line" =~ [├└│─\|] ]]; then
            log_debug "Skipping root directory line: $first_line"
            start_index=1
        fi
    fi
    
    # Now process each line to build the paths
    local -a path_parts=()
    local -a levels=()
    local current_level=-1
    
    for ((i = start_index; i < ${#all_lines[@]}; i++)); do
        local line="${all_lines[$i]}"
        
        # Remove comments
        local clean_line
        clean_line=$(echo "$line" | sed 's/#.*$//')
        
        # Skip if line was just a comment
        if [[ -z "$clean_line" || "$clean_line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi
        
        # Calculate indentation level
        local indent level
        indent=$(echo "$clean_line" | sed -E 's/[^[:space:]│├└─\|].*//' | wc -c)
        indent=$((indent-1)) # Adjust for wc -c counting the newline
        level=$((indent / 2)) # Each level is roughly 2 spaces
        
        log_debug "Line: '$clean_line', Indent: $indent, Level: $level"
        
        # Extract the path component (filename or directory name)
        local path_part
        path_part=$(echo "$clean_line" | sed 's/──/ /g' | tr -d '│├└─\|' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        log_debug "Path part: '$path_part'"
        
        # Update the path stack based on current level
        if [[ $level -gt $current_level ]]; then
            # Going deeper - new child
            log_debug "Deeper level: $level > $current_level"
        elif [[ $level -eq $current_level ]]; then
            # Same level - sibling
            log_debug "Same level: $level = $current_level"
            # Remove last component at this level
            if [[ ${#path_parts[@]} -gt 0 ]]; then
                path_parts=("${path_parts[@]:0:${#path_parts[@]}-1}")
                levels=("${levels[@]:0:${#levels[@]}-1}")
            fi
        else
            # Going back up - remove components until we reach parent level
            log_debug "Back up: $level < $current_level"
            while [[ ${#levels[@]} -gt 0 && ${levels[${#levels[@]}-1]} -ge $level ]]; do
                log_debug "Popping: level ${levels[${#levels[@]}-1]}"
                if [[ ${#path_parts[@]} -gt 0 ]]; then
                    path_parts=("${path_parts[@]:0:${#path_parts[@]}-1}")
                    levels=("${levels[@]:0:${#levels[@]}-1}")
                fi
            done
        fi
        
        # Add current component and level
        path_parts+=("$path_part")
        levels+=("$level")
        current_level=$level
        
        # Construct full path
        local full_path=""
        for part in "${path_parts[@]}"; do
            full_path="${full_path}${part}"
        done
        
        log_debug "Full path: '$full_path'"
        
        # Create the directory or file
        if [[ "$full_path" =~ .*\/$ ]]; then
            # It's a directory (ends with /)
            printf "Creating directory: %s\n" "$full_path"
            mkdir -p "$full_path"
        else
            # It's a file
            printf "Creating file: %s\n" "$full_path"
            # Create parent directory if needed
            local parent_dir
            parent_dir=$(dirname "$full_path")
            if [[ "$parent_dir" != "." ]]; then
                mkdir -p "$parent_dir"
            fi
            
            # Create empty file
            touch "$full_path"
        fi
    done
}

function main() {
    # Set up trap to call cleanup on EXIT, HUP, INT, QUIT, PIPE, TERM
    trap cleanup EXIT HUP INT QUIT PIPE TERM
    
    # Check for no arguments
    if [[ $# -eq 0 ]]; then
        print_help
        exit 1
    fi

    # Process flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -s|--string)
                if [[ -z "${2:-}" ]]; then
                    error_exit "No string provided"
                fi
                echo "$2" | process_tree
                exit 0
                ;;
            *)
                if [[ ! -f "$1" ]]; then 
                    error_exit "File '$1' not found"
                fi
                process_tree < "$1"
                exit 0
                ;;
        esac
    done

    printf "Directory structure created successfully!\n"
}

# Execute the main function
main "$@"