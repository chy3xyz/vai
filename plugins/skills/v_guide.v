// v_guide - Returns the official V language 0.5.x documentation/guide
// This skill provides the latest syntax, features, and best practices for V.
// Use this when you need to check V language syntax or standard library usage.

import os

fn main() {
	// The guide file is expected to be in the same directory
	guide_path := os.join_path(os.dir(@FILE), 'v_guide.md')
	
	content := os.read_file(guide_path) or {
		println('Error: Could not read v_guide.md at ${guide_path}')
		return
	}
	
	println(content)
}
