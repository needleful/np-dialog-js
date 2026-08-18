
module np.dialog.parser;

import std.format;
import std.stdio;
import std.string;
import std.sumtype;
import np.dialog.tokenizer;


enum OpFlags {
	none = 0,
	prefix = 1,
	infix = 2,
	postfix = 4
}

string toString(OpFlags flags) {
	int e = cast(int) flags;
	switch(e) {
		case 0:
			return "none";
		case 1:
			return "prefix";
		case 2:
			return "infix";
		case 3:
			return "prefix & infix";
		case 4:
			return "postfix";
		case 5:
			return "prefix & postfix";
		case 6:
			return "infix & postfix";
		case 7:
			return "prefix, infix & postfix";
		default:
			return "<invalid>";
	}
}

immutable OpFlags[string] operators = [
	"!": OpFlags.prefix,
	"?": OpFlags.postfix,
	":": OpFlags.infix,
	":=": OpFlags.infix,
	"=": OpFlags.infix,
	">": OpFlags.infix,
	"<": OpFlags.infix,
	"<=": OpFlags.infix,
	">=": OpFlags.infix,
	"!=": OpFlags.infix,
	"+=": OpFlags.infix,
	"-=": OpFlags.infix,
	"/=": OpFlags.infix,
	"*=": OpFlags.infix,
	"%": OpFlags.infix,
	"%=": OpFlags.infix,
	"&": OpFlags.infix,
	"&=": OpFlags.infix,
	"&&": OpFlags.infix,
	"&&=": OpFlags.infix,
	"|= ": OpFlags.infix,
	"||= ": OpFlags.infix,
	"+": OpFlags.infix | OpFlags.prefix,
	"-": OpFlags.infix | OpFlags.prefix,
	"*": OpFlags.infix,
	"/": OpFlags.infix,
	"|": OpFlags.infix,
	"||": OpFlags.infix,
	"@": OpFlags.infix,
];

struct ParseResult {
	ParseNode root;
	NPError[] errors;
}
// For sum types
struct Identifier {
	string name;
	string toString() const {
		return name;
	}
}
struct DynamicVar {
	string name;
	string toString() const {
		return "$"~name;
	}
}
struct RawValue {
	string text;
	string toString() const {
		return text;
	}
}
struct PlainText {
	string text;
	string toString() const {
		return text;
	}
}

struct Tag {
	string text;
	// True: opens the tag.
	// False: closes it
	bool start = false;
	string toString() const {
		string s = start? "[" : "[/";
		return s~text~"]";
	}
}
struct Op {
	string text;
	int tokenIndex;

	bool exists() const {
		return (text in operators) != null;
	}

	OpFlags flags() const {
		if(!exists()) {
			return OpFlags.none;
		}
		return operators[text];
	}

	bool supports(OpFlags desiredFlags) const {
		return (desiredFlags & flags()) == desiredFlags;
	}
}

alias TextValue = SumType!(DynamicVar, PlainText, Expression, Tag);

struct Expression {
	alias Value = SumType!(Identifier, DynamicVar, RawValue, PlainText, Expression);
	Value[] head;
	Value[] tail;
	Op[] startOps;
	Op[] endOps;

	void appendTail(T)(T v) {
		Value val = v;
		tail ~= val;
	}
	void appendHead(T)(T v) {
		Value val = v;
		head ~= val;
	}
	// Expressions with special control flow
	bool isControlFlow() const {
		if(head.length != 1) {
			return false;
		}
		if(!head[0].has!Identifier) {
			return false;
		}
		string v = head[0].get!Identifier().name;
		switch(v) {
			case "otherwise": goto case;
			case "goto": goto case;
			case "skip": goto case;
			case "loop": goto case;
			case "break": goto case;
			case "enter": goto case;
			case "back":  goto case;
			case "format":  goto case;
			case "exit":
				return true;
			default:
				return false;
		}
	}

	string toString() const {
		import std.array;
		string[] strings = ["["];
		foreach(s; startOps) {
			strings ~= s.text;
		}
		foreach(h; head) {
			strings ~= h.toString();
		}
		foreach(o; endOps) {
			strings ~= o.text;
		}
		foreach(t; tail) {
			strings ~= t.toString();
		}
		strings ~= "]";
		return strings.join(" ");
	}
}

struct ParseNode {
	enum Type {
		message, narration, option
	}
	int indent, line;
	int tkStart, tkLength;
	ParseNode[] children;
	ParseNode* parent;
	Label[] labels;
	Expression[] conditions;
	Expression[] controlFlow;
	TextValue[] text;
	string speaker;
	Type type;
	void appendText(T)(T v) {
		TextValue tval = v;
		text ~= tval;
	}
	bool isInteresting() const {
		return (text.length || conditions.length || controlFlow.length);
	}
	void recursivePrint(string indent = "") const {
		if(conditions.length) {
			write(indent);
			writefln("? %s", conditions);
		}
		if(controlFlow.length) {
			write(indent);
			writefln("-> %s", controlFlow);
		}

		write(indent);
		if(type == Type.narration) {
			write("* ");
		}
		else if(type == Type.option) {
			write("> ");
		}
		if(text.length) {
			foreach(t; text) {
				write(t);
			}
		}
		writeln();
		string indent2 = indent ~ '\t';
		foreach(child; children) {
			child.recursivePrint(indent2);
		}
	}
}

struct Label {
	alias Arg = SumType!(PlainText, DynamicVar, RawValue);
	string functor;
	string blockName;
	Expression condition;
	Arg[] arguments;
}

ParseResult parse(string text, Token[] tokens) {
	int c = 0;
	Token peek() {
		return tokens[c];
	}
	Token pop(){
		auto tk = peek();
		c ++;
		return tk;
	}
	bool isGood() {
		return c < tokens.length;
	}
	ParseResult result;
	result.root = ParseNode(0, -1, 0, cast(int)tokens.length);
	void pushTkError(string message, int tkIndex) {
		result.errors ~= NPError(message, tkIndex);
	}
	Expression parseExpression() {
		Expression exResult;

		void validateOp(Op operator, OpFlags requiredFlags) {
			if(!operator.exists()) {
				pushTkError(format("Unknown operator: {%s}", operator.text), operator.tokenIndex);
				return;
			}
			if(!operator.supports(requiredFlags)) {
				string msg = format(
					"Operator {%s} was not the required type: %s. Actual: %s",
					operator.text, requiredFlags, operator.flags()
				);
				pushTkError(msg, operator.tokenIndex);
			}
		}
		bool head = true;
		Expression validate() {
			if(exResult.tail.length && exResult.endOps.length > 1) {
				pushTkError("Multiple infix operators not supported", exResult.endOps[1].tokenIndex);
			}
			foreach(Op tkOp; exResult.endOps) {
				validateOp(tkOp, exResult.tail.length? OpFlags.infix : OpFlags.postfix);
			}
			return exResult;
		}
		// Get the head
		while(isGood() && head) {
			auto tk = pop();
			switch(tk.type) {
			case Tok.exIdentifier:
				exResult.appendHead(Identifier(text.tkText(tk)));
				break;
			case Tok.exDynamicVar:
				exResult.appendHead(DynamicVar(text.tkText(tk)));
				break;
			case Tok.exRawValue:
				exResult.appendHead(RawValue(text.tkText(tk)));
				break;
			case Tok.exEnd:
				return validate();
			case Tok.exStart:
				exResult.appendHead(parseExpression());
				break;
			case Tok.exOp:
				if(!exResult.head.length) {
					auto startOp = Op(text.tkText(tk), c-1);
					validateOp(startOp, OpFlags.prefix);
					exResult.startOps ~= startOp;
				}
				else {
					exResult.endOps ~= Op(text.tkText(tk), c-1);
					head = false;	
				}
				break;
			default:
				head = false;
				break;
			}
		}
		while(isGood()) {
			auto tk = pop();
			switch(tk.type) {
			case Tok.exIdentifier:
				exResult.appendTail(Identifier(text.tkText(tk)));
				break;
			case Tok.exDynamicVar:
				exResult.appendTail(DynamicVar(text.tkText(tk)));
				break;
			case Tok.exRawValue:
				exResult.appendTail(RawValue(text.tkText(tk)));
				break;
			case Tok.exText:
				exResult.appendTail(PlainText(text.tkText(tk)));
				break;
			case Tok.exEnd:
				return validate();
			case Tok.exStart:
				exResult.appendTail(parseExpression());
				break;
			case Tok.exArgSplit:
				break;
			default:
				pushTkError("Invalid argument: " ~ text.tkText(tk), c-1);
				return validate();
			}
		}
		return validate();
	}
	// TODO: full parsing of label
	Label parseLabel() {
		Label label;
		Token s = peek();
		if(s.type != Tok.exIdentifier) {
			pushTkError("Expected an identifier after {:}", c);
		}
		else {
			pop();
			label.functor = text.tkText(s);
		}
		Token nl = peek();
		if(nl.type != Tok.newLine) {
			pushTkError("Expected a newline after label declaration", c);
		}
		else {
			pop();
		}
		return label;
	}
	ParseNode* parent = &result.root;
	ParseNode* previous;
	int line = 0;
	int indent = 0;
	Label[] labels = [];
	while(isGood()) {
		ParseNode parsed;
		bool endLine = false;
		bool italics = false;
		bool bold = false;
		bool strike = false;

		bool tagFlip(bool flipped, string tagName) {
			parsed.appendText(Tag(tagName, flipped));
			return flipped;
		}
		while(isGood() && !endLine) {
			Token tkNext = pop();
			switch(tkNext.type) {
			case Tok.newLine:
				endLine = true;
				break;
			case Tok.textPlain:
				parsed.appendText(PlainText(text.tkText(tkNext)));
				break;
			case Tok.symNarration:
				parsed.type = ParseNode.Type.narration;
				break;
			case Tok.symOption:
				parsed.type = ParseNode.Type.option;
				break;
			case Tok.symSpeaker:
				string s = text.tkText(tkNext);
				int l = cast(int) s.length - 2;
				parsed.speaker = s[0..l].strip();
				break;
			case Tok.symLabel:
				labels ~= parseLabel();
				break;
			case Tok.markItalics:
				italics = tagFlip(!italics, "i");
				break;
			case Tok.markBold:
				bold = tagFlip(!bold, "b");
				break;
			case Tok.markStrike:
				strike = tagFlip(!strike, "strike");
				break;
			case Tok.markInterpolate:
				parsed.appendText(parseExpression());
				break;
			case Tok.indent:
			case Tok.unindent:
				indent = tkNext.length;
				break;
			case Tok.exStart:
				Expression ex = parseExpression();
				if(ex.isControlFlow()) {
					parsed.controlFlow ~= ex;
				}
				else {
					parsed.conditions ~= ex;
				}
				break;
			case Tok.markEscape:
				break;
			case Tok.comment:
				break;
			default:
				pushTkError("Unsupported token", c-1);
			}
		}
		parsed.indent = indent;
		if(parsed.isInteresting()) {
			parsed.labels = labels;
			labels = [];
			// Calculate parent based on indentation
			if(previous && parsed.indent > previous.indent) {
				if(parent.children.length) {
					parent = &parent.children[$-1];
				}
			}
			else while(parsed.indent <= parent.indent && parent.parent) {
				parent = parent.parent;
			}
			parent.children ~= parsed;
			previous = &parent.children[$-1];
			previous.parent = parent;
			line++;
		}
	}
	return result;
}