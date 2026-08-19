import std.stdio;

import std.array : appender;
import std.file;
import std.stdio;
import np.dialog.analyzer;
import np.dialog.common;
import np.dialog.javascript;
import np.dialog.parser;
import np.dialog.tokenizer;

void main(string[] args)
{
	testTypes();
	if(args.length <= 1) {
		writeln("No arguments. Running test suite");
		testJS("tests/00_messages.dialog");
		testJS("tests/01_conditions.dialog");
		testJS("tests/02_errors.dialog");
		testJS("tests/03_labels.dialog");
		testJS("tests/04_operators.dialog");
		testJS("tests/05_options.dialog");
		return;
	}
	if(args.length != 4) {
		writeln("usage: <input> <output> <name>");
		return;
	}
	string infile = args[1];
	string outfile = args[2];
	string name = args[3];
	if(!infile.exists()) {
		writefln("File [%s] must be a Dialog file.", infile);
		return;
	}
	string source = infile.readText();
	File outf = File(outfile, "w");

	outf.writeln("// AUTOMATICALLY GENERATED");
	outf.writefln("export const name = '%s';", name);
	outf.writefln("export const %s =", name);
	compileToJS(source, outf.lockingTextWriter());
}

void compileToJS(Writer)(string source, Writer wr) {
	Tokenization tkResult = tokenize(source);
	writeln(tkResult.errors);

	ParseResult parsed = parse(source, tkResult.tokens);
	writeln(parsed.errors);

	DialogSequence seq = analyze(parsed.root);
	writeln(parsed.errors);
	
	NPError[] errors = seq.toJS(wr);
	writeln(errors);
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

void testJS(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return;
	}

	writefln("--- JAVASCRIPT: %s --", filePath);
	auto text = appender!string;
	compileToJS(source, text);
	writeln(text);
}