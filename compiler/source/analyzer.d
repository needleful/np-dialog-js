
module np.dialog.analyzer;

import std.format;
import std.stdio;
import np.dialog.parser;
import np.dialog.tokenizer;


// Similar to ParseNode, but has IDs instead of references
struct DialogItem {
	int id = -1, previous = -1, next = -1;
	int parent = -1, child = -1;
	// Compiled IDs
	int nextOnEnter = -1, nextOnSkip = -1;
	TextValue[] text;
	Expression[] conditions;
	Expression[] controlFlow;
	string speaker;
	ParseNode.Type type;
	this(int p_id, ref ParseNode ps) {
		id = p_id;
		text = ps.text;
		conditions = ps.conditions;
		controlFlow = ps.controlFlow;
		type = ps.type;
	}
	bool usesOtherwise() {
		foreach(ref cf; controlFlow) {
			if(cf.isIdentifier("otherwise")) {
				return true;
			}
		}
		return false;
	}
	void printDebug(string indent = "") {
		writefln("%s%d: [", indent, id);
		writefln("%s\t%s", indent, type);
		if(text.length) writefln("%s\t%s -- %s", indent, speaker, text);
		if(conditions.length) writefln("%s\t? %s", indent, conditions);
		if(controlFlow.length) writefln("%s\t-> %s", indent, controlFlow);
		writefln("%s\tid: %d, previous: %d, next: %d",
			indent, id, previous, next
		);
		writefln("%s\tparent: %d, child: %d",
			indent, parent, child
		);
		writefln("%s\tnextOnEnter: %d, nextOnSkip: %d",
			indent, nextOnEnter, nextOnSkip
		);
		writefln("%s]", indent);
	}
}

struct DialogSequence {
	int[string] labels;
	DialogItem[] dialog;
	NPError[] errors;
	int start;
	void debugPrint() {
		writeln("labels: [");
		foreach(label, id; labels) {
			writefln("\t%s -> %d", label, id);
		}
		writeln("]");
		writeln("dialog: [");
		foreach(d; dialog) {
			d.printDebug("\t");
		}
		writeln("]");
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

			// TODO: advanced label stuff
			foreach(label; child.labels) {
				if(label.functor in result.labels) {
					result.errors ~= NPError(
						format("Duplicate label: %s", label.functor),
						item.id
					);
				}
				result.labels[label.functor] = item.id;
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

DialogSequence analyze(ParseNode parsed) {
	DialogSequence seq = flatten(parsed);
	return seq;
}