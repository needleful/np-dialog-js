module np.dialog.tokenizer;

import std.regex;
import std.string;
import np.dialog.common;

enum Tok {
	invalid,
	newLine,
	textPlain,
	comment,
	indent,
	unindent,

	symNarration,
	symSpeaker,
	symLabel,
	symOption,

	markEscape,
	markItalics,
	markBold,
	markStrike,
	markInterpolate,

	exStart,
	exEnd,
	exIdentifier,
	exOp,
	exArgSplit,
	exText,
	exRawValue,
	exDynamicVar,
	exEscape,

	labelArgsStart,
	labelArgsEnd,
	labelArgsSplit,
	labelOpBlockName,
	labelCatchAll,
}

struct Token {
	Tok type;
	int start;
	int length;
	string readable(string source) {
		import std.format;
		return format("[%s] `%s`", type, source.tkText(this));
	}
}

struct Tokenization {
	Token[] tokens;
	NPError[] errors;
}

static immutable string[] operators = [
	"+=",
	"-=",
	"/=",
	"*=",
	"%=",
	"&&=",
	"||=",
	"<=",
	">=",
	"@=",

	"+",
	"-",
	"/",
	"*",
	"%",
	"&&",
	"||",
	":=",
	":",
	"=",
	"!=",
	"<",
	">",
	"@",
	"!",
	"?"
];

string tkText(string text, ref Token token) {
	return text[token.start..token.start+token.length];
}

Tokenization tokenize(string text) {
	int c = 0;
	Tokenization result;
	string lowerText = text.toLower();

	static rxWhitespace = ctRegex!r"^[\t ]+";
	static any = ctRegex!r"^.";

	string front() {
		return lowerText[c..$];
	}
	void pushTk(Tok type, int length, int start = -1) {
		if(start < 0) {
			start = c;
		}
		result.tokens ~= Token(type, start, length);
		c = start + length;
	}
	void pushTextTk(Tok type, string text, int start = -1) {
		pushTk(type, cast(int) text.length, start);
	}
	void pushErrorTk(string message, string errorText, int start = -1) {
		pushTk(Tok.invalid, cast(int) errorText.length, start);
		result.errors ~= NPError(message, cast(int) result.tokens.length - 1);
	}
	bool isGood() {
		return c < text.length;
	}
	uint skipWhiteSpace() {
		int skipped = 0;
		while(isGood() && (text[c] == ' ' || text[c] == '\t')) {
			skipped ++;
			c ++;
		}
		return skipped;
	}
	string matchesString(Tok type, string match, bool skipSpace = true) {
		if(!isGood()) {
			return null;
		}
		int start = c;
		if(skipSpace) skipWhiteSpace();
		if(front().startsWith(match)) {
			pushTextTk(type, match);
			return match;
		}
		else {
			c = start;
			return null;
		}
	}
	string matchesRegex(Tok type, Regex!char match, bool skipSpace = true) {
		if(!isGood()) {
			return null;
		}
		int start = c;
		if(skipSpace) skipWhiteSpace();
		auto m = front().matchFirst(match);
		if(!m.empty()){
			pushTextTk(type, m.front());
			return m.front();
		}
		else {
			c = start;
			return null;
		}
	}
	string matchesIdentifer() {
		static rx = ctRegex!r"^[\p{L}_][\p{L}\d_]*\b";
		return matchesRegex(Tok.exIdentifier, rx);
	}
	string matchesDynVar() {
		static rx = ctRegex!r"^\$[\p{L}_][\-'+\p{L}\d_]*\b";
		return matchesRegex(Tok.exDynamicVar, rx);
	}
	string matchesInlineVar() {
		static rx = ctRegex!r"^\#[\p{L}_][\-'+\p{L}\d_]*\b";
		return matchesRegex(Tok.exDynamicVar, rx);
	}
	string matchesRawValue() {
		// TODO: a recursive tokenization to allow for nested structures
		static rx = ctRegex!r"^\#[^\]\|\:]+";
		return matchesRegex(Tok.exRawValue, rx);
	}
	string matchesOp() {
		foreach(s; operators) {
			if(string r = matchesString(Tok.exOp, s)) {
				return r;
			}
		}
		return null;
	}
	void tokenizeExpression() {
		int start = c;
		// Optional starting operator
		matchesOp();
		// Required starting identifier or sub-expression
		bool valid = false;
		if(matchesString(Tok.exStart, "[")) {
			tokenizeExpression();
			valid = true;
		}
		else {
			valid = (
				matchesIdentifer()
				|| matchesDynVar()
				|| matchesRawValue()
			);
		}
		if(!valid) {
			if(matchesString(Tok.exStart, "[")) {
			}
			else {
				pushErrorTk("Could not parse expression: no starting identifier", "", start);
			}
		}
		// Function head
		while(isGood()) {
			if(matchesIdentifer()) continue;
			if(matchesOp())
				break;
			if(matchesString(Tok.exEnd, "]")) {
				return;
			}
			if(matchesString(Tok.exStart, "[")) {
				tokenizeExpression();
			}
			matchesRegex(Tok.invalid, any);
		}
		// Function arguments
		while(isGood()) {
			static exText = ctRegex!r"^[^\[\]\\|]+";
			if(matchesString(Tok.exArgSplit, "|")
				|| matchesDynVar()
				|| matchesRawValue()
				|| matchesRegex(Tok.exText, exText)
			) {
				continue;
			}
			if(matchesString(Tok.exStart, "[")) {
				tokenizeExpression();
				continue;
			}
			if(matchesString(Tok.exEnd, "]")) {
				return;
			}
			matchesRegex(Tok.invalid, any);
		}
	}
	void tokenizeLabel() {
		enum LabelTokState {
			start,
			arguments,
			conditions,
			blockName,
		}
		static const textRx = ctRegex!r"^[^,)\n\r]+";
		static const valueRx = ctRegex!r"^#[^,)\n\r]+";
		static const catchAllRx = ctRegex!r"^_\b";
		if(!matchesIdentifer()){
			pushErrorTk("TK: Expected identifier after {:} for label.", matchesRegex(Tok.invalid, any));
			return;
		}
		if(matchesString(Tok.labelArgsStart, "(")) {
			while(isGood() && !matchesString(Tok.labelArgsEnd, ")")) {
				int start = c;
				bool match = matchesString(Tok.labelArgsSplit, ",")
					|| matchesString(Tok.exOp, "!")
					|| matchesDynVar()
					|| matchesRegex(Tok.exRawValue, valueRx)
					|| matchesRegex(Tok.labelCatchAll, catchAllRx)
					|| matchesRegex(Tok.textPlain, textRx);
				if(!match) {
					pushErrorTk("Unexpected token in argument list", matchesRegex(Tok.invalid, any));
					break;
				}
			}
		}
		while(matchesString(Tok.exStart, "[")) {
			tokenizeExpression();
		}
		if(matchesString(Tok.labelOpBlockName, "->")) {
			if(!matchesIdentifer()) {
				pushErrorTk("Expected identifier after block name operator [->]", matchesRegex(Tok.invalid, any));
			}
		}
	}
	// 0: start of line (allows narration, reply, and speaker markings. Checks for indentation)
	// 1: control flow (allows conditions)
	// 2: text and interpolation only
	enum State {
		// Only whitespace and comments
		start,
		// Symbols for things like narration
		symbol,
		// Control flow
		flow,
		// Text and interpolations
		text
	}
	State state = State.start;
	int indentation = 0;
	static comment = ctRegex!r"^\s*\/\/[^\n\r]*";
	static speaker = ctRegex!r"^[^\n\r-\[\]]+\s*--";
	static textPlain = ctRegex!r"^[^\n\r\/\\_#~]+";
	static newlines = ctRegex!r"^[\n\r]+";

	while(isGood()){
		if(state == State.start) {
			if(matchesRegex(Tok.comment, comment)) {
				continue;
			}
			int skipped = skipWhiteSpace();
			if(skipped > indentation) {
				pushTk(Tok.indent, skipped, c - skipped);
			}
			else if(skipped < indentation) {
				pushTk(Tok.unindent, skipped, c - skipped);
			}
			indentation = skipped;
			state = State.symbol;
			continue;
		}
		if(state < State.flow) {
			if(matchesString(Tok.symLabel, ":")) {
				tokenizeLabel();
				state = State.start;
				continue;
			}
			if(matchesString(Tok.symNarration, "*")
				|| matchesRegex(Tok.symSpeaker, speaker)
				|| matchesString(Tok.symOption, ">")
			) {
				skipWhiteSpace();
				state = State.flow;
				continue;
			}
		}
		if(state < State.text) {
			if(matchesString(Tok.exStart, "[")) {
				tokenizeExpression();
				skipWhiteSpace();
				continue;
			}
		}
		if(matchesString(Tok.markInterpolate, "#[")) {
			tokenizeExpression();
			state = State.text;
			continue;
		}
		if(matchesString(Tok.markEscape, "\\")) {
			if(isGood()) { 
				pushTk(Tok.textPlain, 1);
			}
			state = State.text;
			continue;
		}
		if(matchesString(Tok.markItalics, "/")
			|| matchesString(Tok.markBold, "_")
			|| matchesString(Tok.markStrike, "~")
			|| matchesInlineVar()
			|| matchesRegex(Tok.textPlain, textPlain, false)
		) {
			state = State.text;
			continue;
		}
		if(matchesRegex(Tok.newLine, newlines)) {
			state = State.start;
			continue;
		}
		matchesRegex(Tok.invalid, any);
	}

	return result;
}