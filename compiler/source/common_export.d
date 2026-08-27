
module np.dialog.common_export;


struct Export {
	static immutable string[string] opRemap = [
		":=": "=",
		"=": "=="
	];

	// Operators that can be chained
	// Note: using the MAPPED operators!
	static immutable string[] opChained = [
		"+",
		"=",
		"-",
		"/",
		"&&",
		"&",
		"|",
		"||",
		"%"
	];

	// Operators that are NOT just another operator plus assignment
	// Which is assumed the default for any multi-char op ending in "="
	// Note: using the NON-mapped operators!
	static immutable string[] opUniqueEq = [
		"!=",
		":=",
		">=",
		"<=",
	];

	// Requires rewriting `x = y = z` as `x = y && x = z`
	// Note: using the NON-mapped operators!
	static immutable string[] opBoolChain = [
		"=",
		"!=",
		">",
		"<",
	];

	static string quote(string text) {
		import std.string: replace;
		return "\"" ~ text.replace("\\", "\\\\").replace("\"", "\\\"") ~ "\"";
	}
}