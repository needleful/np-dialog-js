
module np.dialog.parser;

import std.format;
import std.stdio;
import std.string;
import std.sumtype;

import np.dialog.common;
import np.dialog.tokenizer;

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
	string var;
	string toString() const {
		return var;
	}
}
struct RawValue {
	string value;
	string toString() const {
		return value;
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
	bool isEmpty() const {
		return head.length == 0 && tail.length == 0;
	}
	void makeEmpty() {
		head = []; tail = []; startOps = []; endOps = [];
	}

	// Expressions with special control flow
	bool isControlFlow() const {
		string v = getIdentifierName();
		if(!v) {
			return false;
		}
		switch(v) {
			case "otherwise": goto case;
			case "goto": goto case;
			case "loop": goto case;
			case "break": goto case;
			case "enter": goto case;
			case "back":  goto case;
			case "exit":
				return true;
			default:
				return false;
		}
	}

	bool isCtEffect() const {
		string v = getIdentifierName();
		return v && (v == "format" || v == "skip" || v == "effect");
	}

	string getIdentifierName() const {
		if(head.length != 1) {
			return null;
		}
		if(!head[0].has!(const(Identifier))) {
			return null;
		}
		return head[0].get!(const(Identifier)).name;
	}

	bool isIdentifier(string name) const {
		string v = getIdentifierName();
		return v && v == name;
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
	int indent;
	int tkStart, tkLength;
	ParseNode[] children;
	ParseNode* parent;
	Label[] labels;
	Expression[] conditions;
	// Effect methods are evaluated after or during item display
	Expression[] effects;
	Expression controlFlow;
	TextValue[] text;
	string speaker;
	Type type;
	void appendText(T)(T v) {
		TextValue tval = v;
		text ~= tval;
	}
	bool isInteresting() const {
		return (text.length || conditions.length || !controlFlow.isEmpty() || effects.length);
	}
	void recursivePrint(string indent = "") const {
		foreach(ref label; labels) {
			write(indent);
			writeln(label);
		}
		if(conditions.length) {
			write(indent);
			writefln("? %s", conditions);
		}
		if(!controlFlow.isEmpty()) {
			write(indent);
			writefln("-> %s", controlFlow);
		}
		if(effects.length) {
			write(indent);
			writefln("$ %s", controlFlow);
		}

		write(indent);
		if(type == Type.narration) {
			write("* ");
		}
		else if(type == Type.option) {
			write("> ");
		}
		foreach(t; text) {
			write(t);
		}
		writeln();
		string indent2 = indent ~ '\t';
		foreach(child; children) {
			child.recursivePrint(indent2);
		}
	}
}

struct Label {
	struct CatchAll{
		string toString() const {
			return "_";
		}
	}
	alias Arg = SumType!(PlainText, DynamicVar, RawValue, CatchAll);
	string functor;
	string blockName;
	Expression[] conditions;
	Arg[] arguments;
	string toString() const {
		return format(":%s(%s) %s -> %s", functor, arguments, conditions, blockName);
	}
	void appendArg(T)(T v) {
		Arg arg = v;
		arguments ~= arg;
	}
	string generateBlockName() const {
		import std.conv;
		if(blockName)
			return blockName;
		else
			return format("%s%s%s", functor, arguments, conditions.length > 0 ? conditions.to!string() : "");
	}
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
	result.root = ParseNode(0, -1, cast(int)tokens.length);
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
				exResult.appendTail(PlainText(text.tkText(tk).strip()));
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
		Token next = pop();
		if(next.type == Tok.labelArgsStart) {
			bool argsDone = false;
			bool argAdded = false;
			void addArg() {
				if(argAdded) {
					pushTkError("Expected a comma {,} between arguments", c-1);
				}
				argAdded = true;
			}
			while(isGood() && !argsDone) {
				next = pop();
				switch(next.type) {
					case Tok.textPlain:
						label.appendArg(PlainText(text.tkText(next)));
						addArg();
						break;
					case Tok.exDynamicVar:
						label.appendArg(DynamicVar(text.tkText(next)));
						addArg();
						break;
					case Tok.exRawValue:
						label.appendArg(RawValue(text.tkText(next)));
						addArg();
						break;
					case Tok.labelArgsSplit:
						if(!argAdded) {
							pushTkError("Extra comma {,} in label arguments: ", c-1);
						}
						argAdded = false;
						break;
					case Tok.labelCatchAll:
						label.appendArg(Label.CatchAll());
						addArg();
						break;
					case Tok.labelArgsEnd:
						argsDone = true;
						if(!argAdded && label.arguments.length) {
							pushTkError("Extra comma {,} at the end of the argument list", c-2);
						}
						break;
					default:
						pushTkError("Unexpected token in label arguments: ", c-1);
				}
			}
			next = pop();
		}
		while(next.type == Tok.exStart && isGood()) {
			label.conditions ~= parseExpression();
			next = pop();
		}
		if(next.type == Tok.labelOpBlockName) {
			next = pop();
			if(next.type != Tok.exIdentifier) {
				pushTkError("Expected an identifier after the block name arrow [->]", c-1);
			}
			else {
				label.blockName = text.tkText(next);
			}
			next = pop();
		}
		if(next.type != Tok.newLine) {
			pushTkError("Expected a newline after label declaration", c-1);
		}
		return label;
	}
	ParseNode* parent = &result.root;
	ParseNode* previous;
	int indent = 0;
	Label[] labels = [];
	while(isGood()) {
		ParseNode parsed = ParseNode(indent, c);
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
			case Tok.exDynamicVar:
				parsed.appendText(DynamicVar(text.tkText(tkNext)));
				break;
			case Tok.indent:
			case Tok.unindent:
				indent = tkNext.length;
				break;
			case Tok.exStart:
				Expression ex = parseExpression();
				if(ex.isControlFlow()) {
					if(!parsed.controlFlow.isEmpty()) {
						pushTkError("Only one control-flow instruction allowed per dialog item", c-1);
					}
					parsed.controlFlow = ex;
				}
				else if(ex.isCtEffect()) {
					parsed.effects ~= ex;
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
				pushTkError("Unsupported text token", c-1);
			}
		}
		parsed.tkLength = c - parsed.tkStart;
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
		}
	}
	return result;
}