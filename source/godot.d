
module np.dialog.godot;

import std.algorithm: canFind;
import std.array;
import std.format;
import std.string;
import std.sumtype;

import np.dialog.analyzer;
import np.dialog.common;
import np.dialog.common_export;
import np.dialog.parser;

static immutable string[string] gdTagNames = [
	"b":"b",
	"i":"i",
	"strike":"s"
];

string makeBBText(ref DialogItem item, out bool hasInterpolation) {
	auto text = appender!string;
	foreach(ref tval; item.text) {
		text.formattedWrite("%s", tval.match!(
			(PlainText pt) => pt.text,
			(Tag tg) => "["~ (tg.start ? "" : "/") ~ gdTagNames[tg.text] ~"]",
			(_) {hasInterpolation = true; return "{}";}
		));
}
	return Export.quote(text.data);
}

string gdTypeName(ParseNode.Type type) {
	import std.conv;
	return "NPDialogItem.Type."~type.to!string();
}

struct GDWriter(Writer) {
	DialogSequence* seq;
	Writer wr;
	NPError[] errors;

	@disable this();
	
	this(ref DialogSequence p_seq, ref Writer p_wr){
		seq = &p_seq;
		wr = p_wr;
	}

	void toGodot() {
		addIndented("extends NPDialogSequence");
		addIndented("func _init():");
		{
			indent();
			addIndented("start = %d", seq.start);
			addLabels();
			addNodeDict();
			// _init function
			unindent();
		}

		addFindFunctions();
		addNodeFunctions();
	}
	void addLabels() {
		addIndented("labels = {");
		indent();
		foreach(label, id; seq.simpleLabels) {
			addIndented("%s: %d,", Export.quote(label), id);
		}
		unindent();
		addIndented("}");
	}
	void addNodeDict() {
		addIndented("nodes = {");
		indent();
		foreach(ref item; seq.dialog) {
			addIndentation();
			bool hasCond = item.conditions.length > 0;
			bool hasEffect = item.effects.length > 0;
			bool hasControlFlow = !item.isTrivialControlFlow();
			bool hasInterpolation = false;
			string createFn;
			switch(item.type) {
				case ParseNode.Type.message:
					createFn = "msg(";
					break;
				case ParseNode.Type.narration:
					createFn = "nr(";
					break;
				case ParseNode.Type.option:
					createFn = "opt(";
					break;
				default:
					createFn = format("NPDialogItem.new(%s, ", item.type.gdTypeName);
					break;
			}
			add("%d: %s%d, %d", item.id, createFn, item.nextOnEnter, item.nextOnSkip);
			if(item.text.length || item.speaker) {
				add(", %s", item.makeBBText(hasInterpolation));
			}
			if(item.speaker) {
				add(", %s", Export.quote(item.speaker));
			}
			add(")");
			if(hasCond || hasEffect || hasControlFlow || hasInterpolation) {
				string cond = hasCond? format("fnCond%d", item.id) : "null";
				string eff = hasEffect? format("fnEffect%d", item.id) : "null";
				string cf;
				if(hasControlFlow) {
					if(item.controlFlow.isIdentifier("back")) {
						cf = "back";
					}
					else {
						cf = format("fnNext%d", item.id);
					}
				}
				else {
					cf = "null";
				}
				string interp = hasInterpolation? format("fnInterp%d", item.id) : "null";
				add(".with_fn(%s,%s,%s,%s)", cond, cf, eff, interp);
			}
			if(item.options.length) {
				add(".with_options(%s)", item.options);
			}
			addLine(",");
		}
		unindent();
		addIndented("}");
	}

	void addFindFunctions() {
		foreach(functor, ref set; seq.labelSets) {
			foreach(count; set.argumentCounts) {
				// Standard function
				addIndentation();
				add("func find_%s%d(_ctx: DialogEvaluator", functor, count);
				if(count > 0) {
					for(int i = 0; i < count; i++) {
						add(", _arg%d", i);
					}
				}
				addLine(") -> int:");
				indent();
				addStandardFind(set, count);
				unindent();
			}
			addSpecialFind(functor, set);
		}
	}

	void addStandardFind(ref LabelSet set, int argCount) {
		bool guaranteed = false;
		LabelEval[] relevantLabels;
		// Local variables used by the function
		localVarReplacements.clear();
		// Gather relevant labels and their variables
		foreach(ref label; set.labels) {
			if(label.arguments.length != argCount) {
				continue;
			}
			relevantLabels ~= label;
		}
		foreach(name; localVarReplacements) {
			addIndented("var %s;", name);
		}
		foreach(ref label; relevantLabels) {
			if(guaranteed) {
				errors ~= NPError("Label will never be hit.", label.destination);
			}
			if(!label.arguments.length && !label.conditions.length) {
				addIndented("return %d", label.destination);
				guaranteed = true;
				continue;
			}
			addIndentation();
			add("if ");

			bool[string] varsUsed;

			if(label.arguments.length) {
				foreach(ulong i, ref arg; label.arguments) {
					arg.match!(
						(PlainText pt) {
							add("_arg%d == %s", i, Export.quote(pt.text));
						},
						(RawValue rv) {
							add("_arg%d == (%s)", i, rv.rawText());
						},
						(DynamicVar dv) {
							varsUsed[dv.varName()] = true;
							localVarReplacements[dv.varName()] = "_arg%d".format(i);
							add("true");
						},
						(_) => add("true")
					);
					if(i + 1 < label.arguments.length) {
						add(" && ");
					}
				}
			}
			if(label.conditions.length) {
				if(label.arguments.length) {
					add(" && ");
				}
				foreach(i, ref condEx; label.conditions) {
					addExpression(condEx, label.destination);
					if(i + 1 < label.conditions.length) {
						add(" && ");
					}
				}
			}
			addLine(":");
			indent();
			foreach(key, _; varsUsed) {
				addIndented("_ctx.declare(%s, %s)",
					Export.quote(key), localVarReplacements[key]);
			}
			addIndented("return %d", label.destination);
			unindent();
		}
		// Return a special value when we failed to find a label.
		if(!guaranteed) {
			addIndented("return -2");
		}
		localVarReplacements.clear();
	}

	bool addSpecialFind(string functor, ref LabelSet set) {
		if(!set.argumentCounts.length) {
			return false;
		}
		if(set.argumentCounts[0] == 0 && set.argumentCounts.length == 1) {
			return false;
		}
		// Local variables used by the function
		localVarReplacements.clear();

		/// SpecialFind checks if every argument is present in a list
		/// So :note(a, b, c) and :note(c, b, a) check the same items.
		/// There's almost always a small number of subjects combined in more complex ways,
		/// So we construct a mask of the arguments and check for them
		/// If there's more than 64 values, we'll just make an array of integers and compare that.
		ulong[string] maskItems;
		bool anyAllowedLabels = false;

		// TODO: what to do about dynamic arguments in special functions?
		foreach(ref label; set.labels) {
			bool allowed = true;
			foreach(ref arg; label.arguments) {
				if(arg.has!PlainText) {
					string pt = arg.get!PlainText.text;
					if(pt !in maskItems) {
						maskItems[pt] = maskItems.length;
					}
				}
				else if(arg.has!DynamicVar){
					allowed = false;
				}
			}
			anyAllowedLabels |= allowed;
		}
		addIndented("func find_special_%s(_ctx: DialogEvaluator, _args: Array) -> NPDialogFound:", functor);
		indent();
		foreach(name; localVarReplacements) {
			addIndented("var %s", name);
		}
		localVarReplacements["_args"] = "_args";
		bool tooBig = maskItems.length >= 64;
		if(maskItems.length) {
			if(tooBig) {
				addIndented("var argSet: Array[int] = []");
			}
			else {
				addIndented("var argMask := 0");
			}
			addIndented("var valMap := {");
			indent();
			{
				foreach(key, id; maskItems) {
					addIndented("%s: %d,", Export.quote(key), tooBig ? id : 1 << id);
				}
			}
			unindent();
			addIndented("}");

			addIndented("for _iarg in _args:");
			indent();
			{
				if(tooBig) {
					addIndented("argSet.append(valMap[_iarg])");
				}
				else {
					addIndented("if _iarg in valMap:");
					indent();
					addIndented("argMask |= valMap[_iarg]");
					unindent();
				}
			}
			unindent();
			if(tooBig) {
				addIndented("if argSet.size() == 0:");
				indent();
				addIndented("return NPDialogFound.invalid()");
				unindent();
				addIndented("argSet.sort()");
			}
			else {
				addIndented("if argMask == 0:");
				indent();
				addIndented("return NPDialogFound.invalid()");
				unindent();
			}
		}
		bool guaranteed = false;
		foreach(ref label; set.labels) {
			if(guaranteed) {
				errors ~= NPError("Label will never be hit.", label.destination);
			}
			if(!label.arguments.length && !label.conditions.length) {
				addLabelFound(label);
				guaranteed = true;
				continue;
			}
			addIndentation();
			add("if ");

			bool[string] varsUsed;
			bool wrote;

			string[] argReq;
			ulong[] usedVars;
			if(label.arguments.length) {
				foreach(ulong i, ref arg; label.arguments) {
					arg.match!(
						(PlainText pt) {
							usedVars ~= maskItems[pt.text];
						},
						(RawValue rv) {
							argReq ~= format("_args[%d] == (%s)", i, rv.rawText());
						},
						(DynamicVar dv) {
							varsUsed[dv.varName()] = true;
							localVarReplacements[dv.varName()] = "_args[%d]".format(i);
						},
						(_) {}
					);
				}
				if(argReq.length) {
					add(argReq.join(" && "));
					wrote = true;
				}
				if(usedVars.length){
					wrote = true;
					if(argReq.length) {
						add(" && ");
					}
					if(tooBig) {
						add("containsAll(%s, argSet)", usedVars);
					}
					else {
						ulong result;
						foreach(i; usedVars) {
							result = result | 1<<i;
						}
						add("matches(%d, argMask)", result);
					}
				}
			}
			if(label.conditions.length) {
				wrote = true;
				if(argReq.length + usedVars.length) {
					add(" && ");
				}
				foreach(i, ref condEx; label.conditions) {
					addExpression(condEx, label.destination);
					if(i + 1 < label.conditions.length) {
						add(" && ");
					}
				}
			}
			if(!wrote) {add("true");}
			addLine(":");
			indent();
			foreach(dv, _; varsUsed) {
				addIndented("_ctx.declare(%s, %s)",
					Export.quote(dv), localVarReplacements[dv]);
			}
			addLabelFound(label);
			unindent();
		}
		addIndented("return NPDialogFound.invalid()");
		unindent();
		return true;
	}

	void addLabelFound(ref LabelEval label) {
		addIndentation();
		add("return NPDialogFound.new(%d, %s, [", label.destination, Export.quote(label.blockName));
		foreach(i, ref arg; label.arguments) {
			bool added = arg.match!(
				(PlainText pt) {
					add(Export.quote(pt.text));
					return true;
				},
				(RawValue rv) {
					add("("); add(rv.rawText()); add(")");
					return true;
				},
				(DynamicVar dv) {
					addDynamicVar(dv);
					return true;
				},
				(Label.CatchAll _) {return false;}
			);
			if(added && i + 1 < label.arguments.length) {
				add(", ");
			}
		}
		addLine("])");
	}

	void addNodeFunctions() {
		foreach(ref item; seq.dialog) {
			if(item.conditions.length) {
				addIndented("func fnCond%d(_ctx: DialogEvaluator) -> bool:", item.id);
				indent();
				addIndentation();
				add("return ");
				foreach(i, ref condEx; item.conditions) {
					add("!!");
					addExpression(condEx, item.id);
					if(i + 1 < item.conditions.length) {
						add(" && ");
					}
				}
				addLine("");
				unindent();
			}
			if(item.effects.length) {
				addIndented("func fnEffect%d(_ctx: DialogEvaluator) -> Array:", item.id);
				indent();
				addIndented("return [");
				indent();
				foreach(ref effect; item.effects) {
					addIndentation();
					if(effect.isIdentifier("skip")) {
						add("\"SKIP\"");
					}
					else {
						addExpression(effect, item.id);
					}
					addLine(",");
				}
				unindent();
				addIndented("]");
				unindent();
			}
			if(!item.isTrivialControlFlow()) {
				if(!item.controlFlow.isIdentifier("back")) {
					addIndented("func fnNext%d(_ctx: DialogEvaluator) -> int:", item.id);
					indent();
					addIndentation();
					add("return ");
					addControlFlow(item);
					addLine("");
					unindent();
				}
			}
			Expression.Value[] values;
			foreach(TextValue tv; item.text) {
				tv.match!(
					(Expression ex) {
						Expression.Value ev = ex;
						values ~= ev;
					},
					(DynamicVar dv) {
						Expression.Value ev = dv;
						values ~= ev;
					},
					(_) {}
				);
			}
			if(values.length) {
				addIndented("func fnInterp%d(_ctx: DialogEvaluator) -> Array:", item.id);
				indent();
				addIndented("return [");
				indent();
				foreach(ref ev; values) {
					addIndentation();
					addExValue(ev, 1, item.id);
					addLine(",");
				}
				unindent();
				addIndented("]");
				unindent();
			}
		}
	}

	void addControlFlow(ref DialogItem item) {
		void addCfExpression(){
			addExpression(item.controlFlow, item.id);
		}

		void addCompiledControlFlow(string fn) {
			// Check for control flow
			int argCount = (cast(int) item.controlFlow.tail.length) - 1;
			if(argCount < 0) {
				errors ~= NPError("[goto] and [enter] need at least one argument: a string label", item.id);
				addCfExpression();
				return;
			}
			auto arg0 = item.controlFlow.tail[0];
			if(!arg0.has!PlainText) {
				addCfExpression();
				return;
			}

			// TODO: move logic for checking control flow to analysis
			string name = arg0.get!PlainText.text;
			if(name !in seq.labelSets) {
				errors ~= NPError(format("No such label: %s", name), item.id);
			}
			else if(!seq.labelSets[name].argumentCounts.canFind(argCount)) {
				errors ~= NPError(
					format("Label [%s] cannot be called with %d argument(s). Supported counts: %s",
						name, argCount, seq.labelSets[name].argumentCounts), item.id);
			}
			if(fn == "goto") {
				add("find_%s%d(_ctx", name, argCount);
			}
			else {
				add("_ctx.%s_fixed(find_%s%d(_ctx", fn, name, argCount);
			}
			foreach(i, ref arg; item.controlFlow.tail) {
				if(i == 0) {
					continue;
				}
				add(", ");
				addExValue(arg, 1, item.id);
			}
			if(fn == "goto") {
				add(")");
			}
			else {
				add("))");
			}
		}
		string fn = item.controlFlow.getIdentifierName();
		if(fn && (fn == "goto" || fn == "enter")) {
			addCompiledControlFlow(fn);
		}
		else {
			addCfExpression();
		}
	}

	void addExpression(ref Expression ex, int itemId) {
		add("(");
		bool complex = complexOperatorChaining(ex);
		if(complex) {
			// Have to assign to a temporary value to chain operators
			// Usually something like [[get_stat: this] > y | z]
			// Which would translate into ((_ctx.__temp = (_ctx.get_stat("this"))), (_ctx.__temp > y) && (_ctx.__temp > z))
			add("(_ctx.__temp = (");
		}
		foreach(ref op; ex.startOps) {
			if(op.text == "+") {
				add("abs");
			}
			else if(op.text == "->") {
				indent();
				addLine("");
				addIndented("func():");
				indent();
				addIndentation();
				add("return ");
			}
			else {
				add(op.text);
			}
			add("(");
		}
		foreach(i, ref headVal; ex.head) {
			addExValue(headVal, i, itemId);
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
				add(")), _ctx.__temp ");
			}
			addArguments(ex, complex, itemId);
		}

		for(ulong i = ex.startOps.length; i > 0; i--) {
			if(ex.startOps[cast(long)i - 1].text == "->") {
				add(")");
				unindent(2);
			}
			else {
				add(")");
			}
		}
		add(")");
	}

	bool complexOperatorChaining(ref Expression ex) {
		return ex.endOps.length == 1 && ex.tail.length > 1 && Export.opBoolChain.canFind(ex.endOps[0].text);
	}

	void addArguments(ref Expression ex, bool complexChain, int itemId) {
		if(ex.endOps.length != 1) {
			errors ~= NPError("Only one infix operator is allowed.", itemId);
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
		if(opText in Export.opRemap) {
			opText = Export.opRemap[originalOp];
		}
		string trueOp = opText;
		// Strip op-assignment
		if(opText.length > 1 && opText[$-1] == '=' 
			&& !Export.opUniqueEq.canFind(originalOp)) 
		{
			opText = opText[0..$-1];
		}
		if(complexChain) {
			add(" %s ", trueOp);
			foreach(i, ref tail; ex.tail) {
				add("(_ctx.__temp %s ", opText);
				addExValue(tail, 1, itemId);
				add(")");
				if(i+1 < ex.tail.length) {
					add(" && ");
				}
			}
		}
		else {
			// Always comma-separated if it's wrapped in end text
			if(end.length) {
				opText = ",";
			}
			else {
				add("%s", trueOp);
			}
			foreach(i, ref tail; ex.tail) {
				addExValue(tail, 1, itemId);

				if(i+1 < ex.tail.length) {
					add("%s ", opText);
				}
			}
		}
		add(end);
	}

	void addDynamicVar(DynamicVar dv) {
		// Sometimes I need scoped variables.
		if(dv.varName() in localVarReplacements) {
			add(localVarReplacements[dv.varName()]);
		}
		else {
			add("_ctx.get_var("); add(Export.quote(dv.varName())); add(")");
		}
	}

	void addExValue(ref Expression.Value val, ulong index, int itemId) {
		val.match!(
			(Identifier id) {
				if(!index) { add("_ctx."); }
				add(Export.identReplace(id.name));
			},
			(DynamicVar dv) {
				addDynamicVar(dv);
			},
			(RawValue rv) {
				add("("); add(rv.rawText()); add(")");
			},
			(PlainText pt) {
				add(Export.quote(pt.text));
			},
			(Expression ex) {
				addExpression(ex, itemId);
			}
		);
	}

private:
	string[string] localVarReplacements;
	int indentation = 0;
	void indent() {
		indentation += 1;
	}
	void unindent(int amount = 1) {
		indentation -= amount;
	}
	void add(Args...)(string spec, Args args) {
		wr.formattedWrite(spec, args);
	}
	void addLine(Args...)(string spec, Args args) {
		add(spec, args);
		wr.put('\n');
	}
	void addIndentation() {
		for(int i = 0; i < indentation; i++) {
			wr.put('\t');
		}
	}
	void addIndented(Args...)(string spec, Args args) {
		addIndentation();
		addLine(spec, args);
	}
}

NPError[] toGD(Writer)(ref DialogSequence seq, ref Writer wr) {
	auto gd = GDWriter!Writer(seq, wr);
	gd.toGodot();
	return gd.errors;
}