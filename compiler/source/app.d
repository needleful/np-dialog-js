import std.stdio;

import np.dialog.tokenizer;

void main(string[] args)
{
	if(args.length <= 1) {
		writeln("No arguments. Running test suite");
		testTokenize("tests/00_messages.dialog");
		testTokenize("tests/01_conditions.dialog");
		testTokenize("tests/02_errors.dialog");
		testTokenize("tests/03_labels.dialog");
		testTokenize("tests/04_operators.dialog");
		testTokenize("tests/05_options.dialog");
	}
}

Tokenization testTokenize(string filePath) {
	import std.file;
	if(!filePath.exists()){
		writefln("Error: no such file: %s", filePath);
		return Tokenization();
	}
	string source = filePath.readText();
	Tokenization tkResult = tokenize(source);
	writefln("-- TOKENIZED: %s --", filePath);
	foreach(Token tk; tkResult.tokens) {
		writefln(" %s [%s]", tk.type, source.tkText(tk));
	}
	return tkResult;
}