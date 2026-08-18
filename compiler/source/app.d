import std.stdio;

import std.file;
import np.dialog.tokenizer;
import np.dialog.parser;
import np.dialog.analyzer;

void main(string[] args)
{
	testTypes();
	if(args.length <= 1) {
		writeln("No arguments. Running test suite");
		testAnalyze("tests/00_messages.dialog");
		testAnalyze("tests/01_conditions.dialog");
		testAnalyze("tests/02_errors.dialog");
		testAnalyze("tests/03_labels.dialog");
		testAnalyze("tests/04_operators.dialog");
		testAnalyze("tests/05_options.dialog");
	}
}

void testTypes() {
	import std.sumtype;
	alias t = SumType!(Identifier, DynamicVar, RawValue, PlainText, Expression);
	t v0 = Identifier("Hello");
	t v1 = DynamicVar("bad");
	t[] vals = [v0,v1];
	assert(vals[0].has!Identifier);
	assert(vals[1].has!DynamicVar);
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

DialogSequence testAnalyze(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return DialogSequence();
	}
	writefln("--- ANALYZED: %s --", filePath);
	Tokenization tkResult = tokenize(source);
	ParseResult parsed = parse(source, tkResult.tokens);
	DialogSequence seq = analyze(parsed.root);
	seq.debugPrint();
	return seq;
}