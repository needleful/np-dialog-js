import std.stdio;

import std.file;
import np.dialog.tokenizer;
import np.dialog.parser;

void main(string[] args)
{
	if(args.length <= 1) {
		writeln("No arguments. Running test suite");
		testParse("tests/00_messages.dialog");
		testParse("tests/01_conditions.dialog");
		testParse("tests/02_errors.dialog");
		testParse("tests/03_labels.dialog");
		testParse("tests/04_operators.dialog");
		testParse("tests/05_options.dialog");
	}
}

string readAll(string filePath) {
	if(!filePath.exists()){
		writefln("Error: no such file: %s", filePath);
		return "";
	}
	return filePath.readText();
}

Tokenization testTokenize(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return Tokenization();
	}
	Tokenization tkResult = tokenize(source);
	writefln("-- TOKENIZED: %s --", filePath);
	foreach(Token tk; tkResult.tokens) {
		writefln(" %s [%s]", tk.type, source.tkText(tk));
	}
	return tkResult;
}

ParseResult testParse(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return ParseResult();
	}
	writefln("--- PARSED: %s --", filePath);
	Tokenization tkResult = tokenize(source);
	ParseResult parsed = parse(source, tkResult.tokens);
	foreach(err; parsed.errors) {
		Token tk = tkResult.tokens[err.index];
		writefln(" (error) %s: {%s}", err.message, tk.readable(source));
	}
	parsed.root.recursivePrint();
	return parsed;
}