
module np.dialog.analyzer;

import std.format;
import std.stdio;
import std.sumtype;
import np.dialog.common;
import np.dialog.parser;


// Fully analyzed and flattened shape
struct DialogItem {
	int id = -1, previous = -1, next = -1;
	int parent = -1, child = -1;
	// Compiled IDs, evaluating control flow logic
	int nextOnEnter = -1, nextOnSkip = -1;
	// List of replies for option types
	int[] options;
	TextValue[] text;
	Expression[] conditions;
	// Effects that only apply at compile-time
	Expression[] effects;
	Expression controlFlow;
	string speaker;
	ParseNode.Type type;
	this(int p_id, ref ParseNode ps) {
		id = p_id;
		text = ps.text;
		conditions = ps.conditions;
		controlFlow = ps.controlFlow;
		effects = ps.effects;
		type = ps.type;
		speaker = ps.speaker;
	}
	bool canSkipPast() const {
		return isTrivialControlFlow() && !text.length && !conditions.length && !effects.length;
	}
	bool isTrivialControlFlow() const {
		return controlFlow.isEmpty() || usesOtherwise() || usesExit();
	}
	bool usesOtherwise() const {
		return controlFlow.isIdentifier("otherwise");
	}
	bool usesExit() const {
		return controlFlow.isIdentifier("exit");
	}
	bool usesSimpleGoto() const {
		if(controlFlow.isIdentifier("goto")) {
			return controlFlow.tail.length == 1 
				&& controlFlow.tail[0].has!(const(PlainText));
		}
		return false;
	}
	string getGotoName() const {
		if(usesSimpleGoto()) 
		{
			return controlFlow.tail[0].get!(const(PlainText)).text;
		}
		return null;
	}
	void printDebug(string indent = "") const {
		writefln("%s%d: [", indent, id);
		writefln("%s\t%s", indent, type);
		if(text.length) writefln("%s\t%s -- %s", indent, speaker, text);
		if(conditions.length) writefln("%s\t? %s", indent, conditions);
		if(effects.length) writefln("%s\t$ %s", indent, effects);
		if(!controlFlow.isEmpty()) writefln("%s\t-> %s", indent, controlFlow);
		if(options.length) writefln("%s\treplies: %s", indent, options);
		writefln("%s\tnextOnEnter: %d, nextOnSkip: %d",
			indent, nextOnEnter, nextOnSkip
		);
		writefln("%s]", indent);
	}
}

struct LabelEval {
	Expression[] conditions;
	Label.Arg[] arguments;
	int destination;
	string blockName;
}

struct LabelSet {
	LabelEval[] labels;
	uint[] argumentCounts;
}

struct DialogSequence {
	// Labels with no arguments or ids
	int[string] simpleLabels;
	// Functors -> first arg (or _) -> labels
	LabelSet[string] labelSets;
	DialogItem[] dialog;
	NPError[] errors;
	int start;
	void debugPrint() const {
		writeln("simpleLabels: [");
		foreach(label, id; simpleLabels) {
			writefln("\t%s -> %d", label, id);
		}
		writeln("]");

		writeln("labelSets: [");
		foreach(functor, set; labelSets) {
			writefln("\t%s [", functor);
			foreach(label; set.labels) {
				writefln("\t\t%s %s -> %d", label.arguments,
					label.conditions, label.destination);
			}
			writefln("\t\tcounts: %s", set.argumentCounts);
			writeln("\t]");
		}
		writeln("]");

		writeln("dialog: [");
		foreach(d; dialog) {
			d.printDebug("\t");
		}
		writeln("]");
	}
	// Append a complex label
	void appendLabel(ref Label l, int destination) {
		if(l.functor !in labelSets) {
			labelSets[l.functor] = LabelSet();
		}
		labelSets[l.functor].labels ~= 
			LabelEval(l.conditions, l.arguments, destination, l.generateBlockName());
	}
	DialogItem* diaGet(int id) {
		return &dialog[id];
	}
	// Only for zero-argument [goto]
	// TODO: can skip if the arguments are known at compile time
	int* getCompileTimeGotoTarget(string name) {
		if(name !in labelSets) {
			return null;
		}
		foreach(ref label; labelSets[name].labels) {
			if(label.arguments.length > 0) {
				continue;
			}
			if(label.conditions.length > 0) {
				return null;
			}
			else {
				return &label.destination;
			}
		}
		return null;
	}
}

DialogSequence flatten(ParseNode parsed) {
	DialogSequence result;
	// Returns the first ID of the list of nodes
	void flattenRecurse(ParseNode node, int parent) {
		int previous = -1;
		foreach(ref child; node.children) {
			if(!child.speaker) {
				child.speaker = node.speaker;
			}
			result.dialog ~= DialogItem(cast(int)result.dialog.length, child);
			DialogItem* item = &result.dialog[$-1];

			foreach(label; child.labels) {
				result.appendLabel(label, item.id);
				if(!label.arguments.length && !label.conditions.length) {
					if(label.functor in result.simpleLabels) {
						result.errors ~= NPError(
							format("Duplicate simple label: %s", label.functor),
							item.id
						);
					}
					result.simpleLabels[label.functor] = item.id;
				}
			}
			if(previous != -1) {
				result.dialog[previous].next = item.id;
				item.previous = previous;
			}
			if(parent != -1) {
				if(result.dialog[parent].child == -1) {
					result.dialog[parent].child = item.id;
				}
				item.parent = parent;
			}
			previous = item.id;
			flattenRecurse(child, item.id);
		}
	}
	flattenRecurse(parsed, -1);
	return result;
}

// Calculate nextOnEnter and nextOnSkip
// This applies any relationship between child and parent,
// Plus any control flow that can be deduced at compile-time
void analyzeControlFlow(ref DialogSequence seq) {
	int findNext(const(DialogItem)* item) {
		int next = item.next;
		bool skipOptions = item.type == ParseNode.Type.option;
		while(next >= 0) {
			DialogItem* diaNext = seq.diaGet(next);
			if(!diaNext.usesOtherwise() 
				&& (!skipOptions || diaNext.type != ParseNode.Type.option)
			) {
				break;
			}
			next = diaNext.next;
		}
		return next;
	}
	// Evaluate basic control flow
	foreach(ref item; seq.dialog) {
		bool enteredSet = false;
		if(item.usesExit()) {
			enteredSet = true;
			item.nextOnEnter = -1;
		}
		else if(item.usesSimpleGoto()) {
			enteredSet = true;
			string target = item.getGotoName();
			int* s = seq.getCompileTimeGotoTarget(target);
			if(s){
				item.nextOnEnter = *s;
				item.controlFlow.makeEmpty();
			}
		}
		else if(item.child >= 0) {
			DialogItem* child = seq.diaGet(item.child);
			if(child.usesOtherwise()) {
				seq.errors ~= NPError("Item cannot use [otherwise] before any conditions!", item.child);
			}
			enteredSet = true;
			item.nextOnEnter = item.child;
		}

		if(item.next >= 0) {
			int foundNext = findNext(&item);
			if(!enteredSet) {
				item.nextOnEnter = foundNext;
				enteredSet = true;
			}
			if(item.type == ParseNode.Type.option) {
				item.nextOnSkip = foundNext;
			}
			else {
				item.nextOnSkip = item.next;
			}
		}
		if(item.nextOnEnter == -1) {
			int parent = item.parent;
			while(parent >= 0) {
				DialogItem* diaParent = seq.diaGet(parent);
				int parentNext = findNext(diaParent);
				if(parentNext >= 0) {
					if(!enteredSet) {
						item.nextOnEnter = parentNext;
						enteredSet = true;
					}
					item.nextOnSkip = parentNext;
					break;
				}
				else {
					parent = diaParent.parent;
				}
			}
		}
		// TODO: check text tags and interpolations
	}
	// Second phase
	// Skip multi-step control flow
	// Example: going to [otherwise] and things like that
	// Also collects option lists
	int resolveIndirectFlow(int id) {
		while(id >= 0) {
			DialogItem* item = seq.diaGet(id);
			if(item.canSkipPast()) {
				id = item.nextOnEnter;
				item.controlFlow.makeEmpty();
			}
			else {
				break;
			}
		}
		return id;
	}
	foreach(ref DialogItem item; seq.dialog) {
		bool skipAndEnter = item.nextOnEnter == item.nextOnSkip;
		item.nextOnEnter = resolveIndirectFlow(item.nextOnEnter);
		if(skipAndEnter) {
			item.nextOnSkip = item.nextOnEnter;
		}
		else {
			item.nextOnSkip = resolveIndirectFlow(item.nextOnSkip);
		}
		if(item.type == ParseNode.Type.option
			&& (item.previous == -1
				|| seq.diaGet(item.previous).type != ParseNode.Type.option)
		) {
			item.options ~= item.id;
			int nextOption = item.next;
			while(nextOption != -1) {
				DialogItem* option = seq.diaGet(nextOption);
				if(option.type == ParseNode.Type.option) {
					item.options ~= nextOption;
					nextOption = option.next;
				}
				else {
					break;
				}
			}
		}
	}
	// Count up label arguments
	foreach(ref labelSet; seq.labelSets) {
		bool[ulong] counts;
		foreach(ref label; labelSet.labels) {
			counts[label.arguments.length] = true;
		}
		foreach(key, _; counts) {
			labelSet.argumentCounts ~= cast(uint) key;
		}
	}
}

DialogSequence analyze(ParseNode parsed) {
	DialogSequence seq = parsed.flatten();
	seq.analyzeControlFlow();
	return seq;
}