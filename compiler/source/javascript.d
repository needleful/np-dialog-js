
module np.dialog.javascript;

import std.algorithm: canFind;
import std.array;
import std.format;
import std.string;
import std.sumtype;

import np.dialog.common;
import np.dialog.analyzer;
import np.dialog.parser;

struct JSWriter(Writer) {
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
		return "\"" ~ text.replace("\\", "\\\\").replace("\"", "\\\"") ~ "\"";
	}

	DialogSequence* seq;
	Writer wr;
	NPError[] errors;

	@disable this();
	
	this(ref DialogSequence p_seq, ref Writer p_wr){
		seq = &p_seq;
		wr = p_wr;
	}

	void toJS() {
		addLine("{\nintStart: %d,\ndc_str_labels: {", seq.start);
		foreach(label, id; seq.simpleLabels) {
			addLine("\t%s: %d,", quote(label), id);
		}
		// Labels
		addLine("},");

		addLine("fn: {");
		foreach(functor, ref set; seq.labelSets) {
			foreach(count; set.argumentCounts) {
				// Standard function
				add("\tfind_%s%d(ctx, label", functor, count);
				if(count > 0) {
					for(int i = 0; i < count; i++) {
						add(", arg%d", i);
					}
				}
				addLine(") => {");
				addStandardFind(set, count);
				addLine("\t},");
			}
			// Special function
			addLine("\tfind_special_%s(ctx, label, args) => {", functor);
			addSpecialFind(set);
			addLine("\t},");
		}
		// Control flow functions
		addLine("},");

		addLine("dc_int_dialog: {");
		foreach(ref item; seq.dialog) {
			addLine("\t%d: {", item.id);
			addLine("\t\tnextOnEnter: %d, nextOnSkip: %d,",
				item.nextOnEnter, item.nextOnSkip
			);
			if(item.options.length) {
				add("\t\toptions: [");
				foreach(int opt; item.options) {
					add("%d, ", opt);
				}
				addLine("],");
			}
			addCondList(item);
			addEffects(item);
			addControlFlow(item);
			addText(item);
			addLine("\t},");
		}
		// Dialog
		addLine("}");
		
		// Full object
		addLine("}");
	}

private:
	void add(Args...)(string spec, Args args) {
		wr.formattedWrite(spec, args);
	}
	void addLine(Args...)(string spec, Args args) {
		add(spec, args);
		wr.put('\n');
	}
	void addExpression(ref Expression ex, ref DialogItem item) {
		add("(");
		bool complex = complexOperatorChaining(ex);
		if(complex) {
			// Have to assign to a temporary value to chain operators
			// Usually something like [[get_stat: this] > y | z]
			// Which would translate into ((ctx.__temp = (ctx.get_stat("this"))), (ctx.__temp > y) && (ctx.__temp > z))
			add("(ctx.__temp = (");
		}
		foreach(ref op; ex.startOps) {
			if(op.text == "+") {
				add("math.abs");
			}
			else {
				add(op.text);
			}
			add("(");
		}
		foreach(i, ref headVal; ex.head) {
			addExValue(headVal, i, item);
			if(i + 1 < ex.head.length) {
				add(".");
			}
		}

		if(!ex.tail.length) {
			// Only current postfix operator is {?},
			// which turns a function call into a variable access
			// So we just add () if there's no operators
			if(!ex.endOps.length) {
				add("()");
			}
		}
		else {
			if(complex) {
				add(")), ctx.__temp ");
			}
			addArguments(ex, complex, item);
		}

		for(ulong i = 0; i < ex.startOps.length; i++) {
			add(")");
		}
		add(")");
	}
	bool complexOperatorChaining(ref Expression ex) {
		return ex.endOps.length == 1 && ex.tail.length > 1 && opBoolChain.canFind(ex.endOps[0].text);
	}
	void addArguments(ref Expression ex, bool complexChain, ref DialogItem item) {
		if(ex.endOps.length != 1) {
			errors ~= NPError("Only one infix operator is allowed.", item.id);
			return;
		}
		string originalOp = ex.endOps[0].text;
		string opText = originalOp;
		string end = "";
		if(opText == ":") {
			add("(");
			end = ")";
		}
		if(opText == "@") {
			add("[");
			end = "]";
		}
		if(opText in opRemap) {
			opText = opRemap[originalOp];
		}
		string trueOp = opText;
		// Strip op-assignment
		if(opText.length > 1 && opText[$-1] == '=' 
			&& !opUniqueEq.canFind(originalOp)) 
		{
			opText = opText[0..$-1];
		}
		if(complexChain) {
			add(trueOp);
			foreach(i, ref tail; ex.tail) {
				add("(ctx.__temp %s ", opText);
				addExValue(tail, 1, item);
				add(")");
				if(i+1 < ex.tail.length) {
					add(" && ");
				}
			}
		}
		else {
			if(!opChained.canFind(opText)) {
				opText = ",";
			}
			else {
				add(trueOp);
			}
			foreach(i, ref tail; ex.tail) {
				addExValue(tail, 1, item);

				if(i+1 < ex.tail.length) {
					add("%s ", opText);
				}
			}
		}
		add(end);
	}
	void addExValue(ref Expression.Value val, ulong index, ref DialogItem item) {
		val.match!(
			(Identifier id) {
				if(!index) { add("ctx."); }
				add(id.name);
			},
			(DynamicVar dv) {
				add("ctx._vars["); add(quote(dv.var)); add("]");
			},
			(RawValue rv) {
				add("("); add(rv.value[1..$]); add(")");
			},
			(PlainText pt) {
				add(quote(pt.text));
			},
			(Expression ex) {
				addExpression(ex, item);
			}
		);
	}
	void addCondList(ref DialogItem item) {
		if(!item.conditions.length) {
			return;
		}
		add("\t\tcanEnter: (ctx) => ");
		foreach(i, ref condEx; item.conditions) {
			addExpression(condEx, item);
			if(i + 1 < item.conditions.length) {
				add(" && ");
			}
		}
		addLine(",");
	}
	void addEffects(ref DialogItem item) {
		if(!item.effects.length) {
			return;
		}
		addLine("\t\trunEffects: (ctx) => [");
		foreach(i, ref effect; item.effects) {
			add("\t\t\t");
			addExpression(effect, item);
			if(i + 1 < item.effects.length) {
				addLine(", ");
			}
			else {
				wr.put('\n');
			}
		}
		addLine("\t\t],");
	}
	void addControlFlow(ref DialogItem item) {
		if(item.isTrivialControlFlow()) {
			return;
		}
		add("\t\tgetNext: (ctx) => ");
		addExpression(item.controlFlow, item);
		addLine(",");
	}
	void addStandardFind(ref LabelSet set, int argCount) {
		return;
	}
	void addSpecialFind(ref LabelSet set) {
		return;
	}
	void addText(ref DialogItem item) {
		if(!item.text.length) {
			return;
		}

		// Short form for the common case of plain text
		if(item.text.length == 1 
			&& item.text[0].has!PlainText()) 
		{
			add("\t\tshow: (ctx, display) => ");
			string codeTxt = quote(item.text[0].get!PlainText().text);
			if(item.type == ParseNode.Type.message){
				string codeSpeaker;
				if(item.speaker) {
					codeSpeaker = quote(item.speaker);
				}
				else {
					codeSpeaker = "ctx.defaultSpeaker";
				}
				add("display.AddMessage(%s, %s)", codeSpeaker, codeTxt);
			}
			else if(item.type == ParseNode.Type.narration) {
				add("display.addNarration(%s)", codeTxt);
			}
			else if(item.type == ParseNode.Type.option) {
				add("display.addReplyButton(%s)", codeTxt);
			}
			addLine(",");
			return;
		}

		// More complex form
		addLine("\t\tshow: (ctx, display) => {");
		if(item.type == ParseNode.Type.option) {
			addLine("\t\t\tvar e = display.addReplyButton();");
		}
		else if (item.type == ParseNode.type.narration) {
			addLine("\t\t\tvar e = display.addNarration();");
		}
		else {
			string codeSpeaker;
			if(item.speaker) {
				codeSpeaker = quote(item.speaker);
			}
			else {
				codeSpeaker = "ctx.defaultSpeaker";
			}
			addLine("\t\t\tvar e = display.addMessage(%s);", codeSpeaker);
		}
		string[] tagStack;
		bool workingElemDefined = false;
		foreach(ref tv; item.text) {
			add("\t\t\t");
			tv.match!(
				(PlainText pt) {
					add("display.appendText(e, %s);", quote(pt.text));
				},
				(DynamicVar dv) {
					add("display.appendText(e, String(ctx._vars[%s]));", quote(dv.var)); 
				},
				(Expression ex) {
					add("display.appendTextOrElement(e, ");
					addExpression(ex, item);
					add(");");
				},
				(Tag tg) {
					// TODO: move this check logic to analysis
					if(tg.start) {
						tagStack ~= tg.text;
						if(!workingElemDefined) {
							add("var ");
						}
						add("_we = document.createElement('%s');", tg.text);
						add(" e.appendChild(_we); e = _we;");
					}
					else {
						if(!tagStack.length) {
							errors ~= NPError(
								format("Closing tag without opening tag: {%s}", tg.text),
								item.id
							);
						}
						else {
							string realTag = tagStack[$-1];
							tagStack.popBack();
							if(realTag != tg.text) {
								errors ~= NPError(
									format("Mismatched tags: {%s} opened, {%s} closed", realTag, tg.text),
									item.id
								);
							}
						}
						add("e = e.parentElement;");
					}
				}
			);
			addLine("");
		}
		foreach(tag; tagStack) {
			errors ~= NPError(format("Missing end-tag: %s", tag), item.id);
			addLine("\t\t\te=e.parentElement;");
		}
		addLine("\t\t\treturn e;");
		addLine("\t\t},");
	}
}

NPError[] toJS(Writer)(ref DialogSequence seq, ref Writer wr) {
	auto js = JSWriter!Writer(seq, wr);
	js.toJS();
	return js.errors;
}