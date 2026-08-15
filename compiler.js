"use strict";
// This is intended to be loaded as a module.
// The code uses Hungarian notation for all variables,
// with the following prefixes:
// str: String, int: Number (as integer), fl: Number(as float)
// b: boolean, rx: Regular Expresion, var: Variadic (multiple types)
// a_X: Array of X, dc_X_Y: Dictionary of X key to Y value
// Other prefixes will be specified with the constructor function.

const name = 'np_dialog';

const Tok = {
	invalid: 0,
	newLine: 1,
	textPlain: 2,
	comment: 3,
	indent: 4,
	unindent: 5,

	symNarration: 10,
	symSpeaker: 11,

	markEscape: 20,
	markItalics: 21,
	markBold: 22,
	markStrike: 22,
};

// Creates an array of Token (prefix: tk)
function tokenize(strText) {
	let intC = 0;
	let a_tkResult = [];
	const strLower = strText.toLowerCase();
	function pushTk(tokType, intLength, intStart = -1) {
		if(intStart < 0) {
			intStart = intC;
		}
		a_tkResult.push({
			tokType:tokType,
			intStart: intStart,
			intLength: intLength
		});
		intC += intLength;
	}
	function pushTextTk(tokType, strText) {
		pushTk(tokType, strText.length);
	}
	function pushError(strDescription, strText) {
		a_tkResult.push({
			tokType:Tok.invalid,
			varInfo: strDescription,
			intStart: intC,
			intLength: strText.length
		});
		intC += strText.length;
	}
	function isGood() {
		return intC < strText.length;
	}
	function skipWhiteSpace(){
		let m = strText.substr(intC).match(/^[\t ]+/);
		if(m) {
			intC += m[0].length;
			return m[0].length;
		}
		else {
			return 0;
		}
	}
	function matchesString(tokType, strMatch, bSkipSpace = true) {
		if(!isGood()) {
			return false;
		}
		if(bSkipSpace) skipWhiteSpace();
		if(strLower.startsWith(strMatch, intC)) {
			pushTextTk(tokType, strMatch);
			return true;
		}
		else {
			return false;
		}
	}
	function matchesStrings(tokType, a_strMatches) {
		if(!isGood()) {
			return false;
		}
		for(let i = 0; i < a_strMatches.length; i++) {
			if(findString(tokType, a_strMatches[i], i)) {
				return true;
			}
		}
		return false;
	}
	function matchesRegex(tokType, rxMatch, bSkipSpace = true) {
		if(!isGood()) {
			return false;
		}
		if(bSkipSpace) skipWhiteSpace();
		let m = strText.substr(intC).match(rxMatch);
		if(m) {
			pushTextTk(tokType, m[0]);
			return true;
		}
		else {
			return false;
		}
	}

	// Some symbols are different at the start of a line.
	var newLine = true;
	var indentation = 0;
	while(isGood()){
		if(newLine) {
			var intSkipped = skipWhiteSpace();
			if(intSkipped > indentation) {
				pushTk(Tok.indent, intSkipped, intC - intSkipped);
			}
			else if(intSkipped < indentation) {
				pushTk(Tok.unindent, intSkipped, intC - intSkipped);
			}
			indentation = intSkipped;

			if(matchesString(Tok.symNarration, '*')
				|| matchesString(Tok.symSpeaker, '--')
				|| matchesRegex(Tok.comment, /^\/\/[^\n]*/)
			) {
				newLine = false;
				continue;
			}
		}
		if(matchesString(Tok.markEscape, '|')) {
			if(isGood()) { 
				pushTk(Tok.textPlain, 1);
			}
			continue;
		}
		if(matchesString(Tok.markItalics, '/')
			|| matchesString(Tok.markBold, '_')
			|| matchesString(Tok.markStrike, '~')
			|| matchesRegex(Tok.textPlain, /^[^\n\/_|]+/)
		) {
			newLine = false;
			continue;
		}
		if(matchesRegex(Tok.newLine, /^\n+/)) {
			newLine = true;
			continue;
		}
	}
	return a_tkResult;
}

const ItemType = {
	message: 0,
	narration: 1,
	option: 2
};

// Returns an tree of ParseNode (prefix: ps)
function parse(strText, a_tkTokens) {
	var intC = 0;
	function tkText(tk) {
		return strText.substr(tk.intStart, tk.intLength);
	}
	function peek() {
		return a_tkTokens[intC];
	}
	function pop(){
		var tk = peek();
		intC ++;
		return tk;
	}
	function isGood() {
		return intC < a_tkTokens.length;
	}
	var psRoot = {
		a_psChildren: [],
		psParent: null,
		intIndent: 0,
		intLine: -1
	};
	var psParent = psRoot;
	var intLine = 0;
	while(isGood()) {
		var item = {
			type: ItemType.message,
			// String, interpolation, or tag
			a_varText: [],
			a_conditions: [],
			strSpeaker: '',
			a_psChildren: [],
			intIndent: psParent.intIndent,
			intLine: intLine
		};
		var bNext = false;
		var bItalics = false;
		var bBold = false;
		var bStrike = false;

		function tagFlip(bTag, strTag) {
			item.a_varText.push(bTag? {tagStart: strTag} : {tagEnd: strTag});
			return bTag;
		}
		while(isGood() && !bNext) {
			var tkNext = pop();
			switch(tkNext.tokType) {
			case Tok.newLine:
				bNext = true;
				break;
			case Tok.textPlain:
				item.a_varText.push(tkText(tkNext));
				break;
			case Tok.symNarration:
				item.type = ItemType.narration;
				break;
			case Tok.markItalics:
				bItalics = tagFlip(!bItalics, 'i');
				break;
			case Tok.markBold:
				bBold = tagFlip(!bBold, 'b');
				break;
			case Tok.markStrike:
				bStrike = tagFlip(!bStrike, 'strike');
				break;
			case Tok.indent:
			case Tok.unindent:
				item.intIndent = tkNext.intLength;
				break;
			}
		}
		if(item.a_varText.length || item.a_conditions.length){
			if(item.intIndent > psParent.intIndent) {
				var l = psParent.a_psChildren.length - 1;
				if(l >= 0) {
					psParent = psParent.a_psChildren[l];
				}
				else {
					console.error('Duplicate indentation?');
				}
			}
			else while(item.intIndent < psParent.intIndent && psParent.psParent) {
				psParent = psParent.psParent;
			}
			psParent.a_psChildren.push(item);
			item.psParent = psParent;
			intLine++;
		}
	}

	return psRoot;
}

// Dictionary of integers to finalized DialogItems (prefix: dia)
function flatten(psParse) {
	var dc_int_dialog = {};

	// Return parent dialog node's index
	function flatten_recurse(psParse) {
		var diaNode = {
			intNext:-1,
			intParent: -1,
			intChild:-1,
			a_varText: psParse.a_varText,
			a_conditions: psParse.a_conditions,
		};
		if(psParse.a_psChildren.length > 0) {
			diaNode.intChild = psParse.a_psChildren[0].intLine;
		}
		dc_int_dialog[psParse.intLine] = diaNode;

		var intPrev = -1;
		for(let i = 0; i < psParse.a_psChildren.length; i++) {
			var psNext = psParse.a_psChildren[i];
			if(intPrev >= 0) {
				dc_int_dialog[intPrev].intNext = psNext.intLine;
			}
			intPrev = flatten_recurse(psNext);
			dc_int_dialog[intPrev].intParent = psParse.intLine;
		}
		return psParse.intLine;
	}
	flatten_recurse(psParse);
	return dc_int_dialog;
}

// Returns DialogItems from text
function compile(strText) {
	var a_tkTokens = tokenize(strText);
	var psParse = parse(strText, a_tkTokens);
	var dc_int_dialog = flatten(psParse);
	return dc_int_dialog;
}

export {name, compile};