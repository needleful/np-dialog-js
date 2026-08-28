import std.stdio;

import std.array : appender;
import std.file;
import std.stdio;
import np.dialog.analyzer;
import np.dialog.common;
import np.dialog.godot;
import np.dialog.javascript;
import np.dialog.parser;
import np.dialog.tokenizer;

void main(string[] args)
{
	testTypes();
	if(args.length <= 1) {
		writeln("No arguments. Running test suite");
		testAll(&testJS);
		return;
	}
	if(args[1] == "--test") {
		writefln("Testing...");
		if(args.length < 3) {
			writeln("Running default test: compiling to Javascript");
			testAll(&testJS);
			return;
		}
		const (void function(string))[string] actions = [
			"tokenize": &testTokenize,
			"parse": &testParse,
			"analyze": &testAnalyze,
			"js": &testJS,
			"gd": &testGD,
			"javascript": &testJS
		];
		if(args[2] in actions) {
			if(args.length < 4) {
				testAll(actions[args[2]]);
			}
			else {
				testAll(actions[args[2]], args[3]);
			}
		}
		else {
			writefln("No such action: [%s]", args[2]);
			writeln("Supported actions:");
			foreach(string key, _; actions) {
				writefln("\t%s", key);
			}
		}
		return;
	}
	if(args.length < 4) {
		writeln("usage: <input> <output> <type> [other parameters]");
		return;
	}
	string infile = args[1];
	string outfile = args[2];
	string type = args[3];
	if(!infile.exists()) {
		writefln("File [%s] must be a Dialog file.", infile);
		return;
	}
	string source = infile.readText();
	File outf = File(outfile, "w");
	if(type == "js" || type == "javascript") {
		if(args.length < 5) {
			writeln("<name> required after type.");
			return;
		}
		string name = args[4];
		outf.writeln("// AUTOMATICALLY GENERATED");
		outf.writefln("export const name = '%s';", name);
		outf.writefln("export const %s =", name);
		compileToJS(source, outf.lockingTextWriter());
	}
	if(type == "gd" || type == "godot") {
		compileToGD(source, outf.lockingTextWriter());
	}
}

void testAll(void function(string) fnTest, string source = null) {
	if(!source) {
		fnTest("tests/00_messages.dialog");
		fnTest("tests/01_conditions.dialog");
		fnTest("tests/02_errors.dialog");
		fnTest("tests/03_labels.dialog");
		fnTest("tests/04_operators.dialog");
		fnTest("tests/05_options.dialog");
		fnTest("tests/06_goto_args.dialog");
		fnTest("tests/07_goto_errors.dialog");
	}
	else {
		fnTest(source);
	}
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

void compileToGD(Writer)(string source, Writer wr) {
	Tokenization tkResult = tokenize(source);
	writeln(tkResult.errors);

	ParseResult parsed = parse(source, tkResult.tokens);
	writeln(parsed.errors);

	DialogSequence seq = analyze(parsed.root);
	writeln(parsed.errors);
	
	NPError[] errors = seq.toGD(wr);
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

void testTokenize(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return;
	}
	Tokenization tkResult = tokenize(source);
	writefln("-- TOKENIZED: %s --", filePath);
	foreach(Token tk; tkResult.tokens) {
		writefln(" %s [%s]", tk.type, source.tkText(tk));
	}
}

void testParse(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return;
	}
	writefln("--- PARSED: %s --", filePath);
	Tokenization tkResult = tokenize(source);
	ParseResult parsed = parse(source, tkResult.tokens);
	foreach(err; parsed.errors) {
		Token tk = tkResult.tokens[err.index];
		writefln(" (error) %s: {%s}", err.message, tk.readable(source));
	}
	parsed.root.recursivePrint();
}

void testAnalyze(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return;
	}
	writefln("--- ANALYZED: %s --", filePath);
	Tokenization tkResult = tokenize(source);
	ParseResult parsed = parse(source, tkResult.tokens);
	DialogSequence seq = analyze(parsed.root);
	seq.debugPrint();
}

void testJS(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return;
	}

	writefln("--- JAVASCRIPT: %s --", filePath);
	auto text = appender!string;
	compileToJS(source, text);
	writeln(text.data);
}

void testGD(string filePath) {
	string source = readAll(filePath);
	if (!source) {
		return;
	}

	writefln("--- GODOT: %s --", filePath);
	auto text = appender!string;
	compileToGD(source, text);
	writeln(text.data);
}