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
	markInterpolate:23,

	exStart: 30,
	exEnd: 31,
	exIdentifier: 32,
	exStartOp: 33,
	exEndOp: 34,
	exArgSplit: 35,
	exText: 36,
	exRawValue: 37,
	exDynamicVar: 38,
	exEscape: 40
};

let TokNames = {};
for(let k in Tok) {
	TokNames[Tok[k]] = k;
}
Object.freeze(TokNames);

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
		intC = intStart + intLength;
	}
	function pushTextTk(tokType, strText) {
		pushTk(tokType, strText.length);
	}
	function pushErrorTk(strDescription, strText, intStart = -1) {
		var intLength = strText.length;
		if(intStart < 0) {
			intStart = intC;
		}
		else {
			intLength = intC - intStart;
		}
		a_tkResult.push({
			tokType:Tok.invalid,
			varInfo: strDescription,
			intStart: intStart,
			intLength: intLength
		});
		intC += intLength;
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
	function matchesOneOf(tokType, a_strMatches) {
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
	function tokenizeExpression() {
		function grabIdentifer() {
			return matchesRegex(Tok.exIdentifier, /^\p{Alpha}[\p{Alpha}\d_]*\b/u);
		}
		function grabDynVar() {
			return matchesRegex(Tok.exDynamicVar, /^\$\p{Alpha}[\-'+\p{Alpha}\d_]*\b/u)
		}
		function grabRawValue() {
			return matchesRegex(Tok.exRawValue, /^\#[^\]\|]/);
		}
		var intStart = intC;
		// Optional starting operator
		matchesString(Tok.exStartOp, '!');
		// Required starting identifier or sub-expression
		var bValid = (matchesString(Tok.exStart, '[')
			|| grabIdentifer()
			|| grabDynVar()
			|| grabRawValue()
		);
		if(!bValid) {
			if(matchesString(Tok.exStart, '[')) {
				tokenizeExpression();
			}
			else {
				pushErrorTk('Could not parse expression: no starting identifier', '', intStart);
			}
		}
		// Function head
		while(isGood()) {
			if(grabIdentifer()) continue;
			if(matchesRegex(Tok.exEndOp, /^[+\-=/\\|?<>&%$!@:]+/))
				break;
			if(matchesString(Tok.exEnd, ']')) {
				return;
			}
			if(matchesString(Tok.exStart, '[')) {
				tokenizeExpression();
			}
			matchesRegex(Tok.invalid, /^./);
		}
		// Function arguments
		while(isGood()) {
			if(matchesString(Tok.exArgSplit, '|')
				|| grabDynVar()
				|| grabRawValue()
				|| matchesRegex(Tok.exText, /^[^\]\\|]/)
			) {
				continue;
			}
			if(matchesString(Tok.exStart, '[')) {
				tokenizeExpression();
				continue;
			}
			if(matchesString(Tok.exEnd, ']')) {
				return;
			}
			matchesRegex(Tok.invalid, /^./);
		}
	}

	// 0: start of line (allows narration, reply, and speaker markings. Checks for indentation)
	// 1: control flow (allows conditions)
	// 2: text and interpolation only
	var intState = 0;
	var indentation = 0;
	while(isGood()){
		if(intState < 1) {
			var intSkipped = skipWhiteSpace();
			if(intSkipped > indentation) {
				pushTk(Tok.indent, intSkipped, intC - intSkipped);
			}
			else if(intSkipped < indentation) {
				pushTk(Tok.unindent, intSkipped, intC - intSkipped);
			}
			indentation = intSkipped;

			if(matchesString(Tok.symNarration, '*')
				|| matchesRegex(Tok.symSpeaker, /^[^\s-[\]]+\s*--/)
				|| matchesRegex(Tok.comment, /^\/\/[^\n]*/)
			) {
				intState = 1;
				continue;
			}
		}
		if(intState < 2) {
			if(matchesString(Tok.exStart, '[')) {
				tokenizeExpression();
				continue;
			}
		}
		if(matchesString(Tok.markEscape, '\\')) {
			if(isGood()) { 
				pushTk(Tok.textPlain, 1);
			}
			continue;
		}
		if(matchesString(Tok.markInterpolate, '#[')) {
			tokenizeExpression();
			intState = 2;
			continue;
		}
		if(matchesString(Tok.markItalics, '/')
			|| matchesString(Tok.markBold, '_')
			|| matchesString(Tok.markStrike, '~')
			|| matchesString(Tok.textPlain, '#')
			|| matchesRegex(Tok.textPlain, /^[^\n\/\\_#]+/)
		) {
			intState = 2;
			continue;
		}
		if(matchesRegex(Tok.newLine, /^\n+/)) {
			intState = 0;
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
	function parseExpression() {
		var exResult = {
			a_head: [],
			a_tail: [],
			strStartOp: undefined,
			strEndOp: undefined,
		}
		var head = true;
		// Get the head
		while(isGood() && head) {
			var tk = pop();
			switch(tk.tokType) {
			case Tok.exIdentifier:
				exResult.a_head.push(tkText(tk));
				break;
			case Tok.exDynamicVar:
				exResult.a_head.push({strVar: tkText(tk)});
				break;
			case Tok.exRawValue:
				exResult.a_head.push({strRaw: tkText(tk)});
				break;
			case Tok.exEnd:
				return exResult;
			case Tok.exStart:
				exResult.a_head.push(parseExpression());
				break;
			case Tok.exEndOp:
				exResult.strEndOp = tkText(tk);
				head = false;
				break;
			default:
				head = false;
				break;
			}
		}
		while(isGood()) {
			var tk = pop();
			switch(tk.tokType) {
			case Tok.exIdentifier:
				exResult.a_tail.push(tkText(tk));
				break;
			case Tok.exDynamicVar:
				exResult.a_tail.push({strVar: tkText(tk)});
				break;
			case Tok.exRawValue:
				exResult.a_tail.push({strRaw: tkText(tk)});
				break;
			case Tok.exEnd:
				return exResult;
			case Tok.exStart:
				exResult.a_tail.push(parseExpression());
				break;
			default:
				console.error('Invalid argument: ', tkText(tk), tk)
				return exResult;
			}
		}
		return exResult;
	}
	var psParent = psRoot;
	var intLine = 0;
	var indent = 0;
	while(isGood()) {
		var item = {
			type: ItemType.message,
			// String, interpolation, or tag
			a_varText: [],
			a_conditions: [],
			strSpeaker: '',
			a_psChildren: [],
			intIndent: indent,
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
			case Tok.symSpeaker:
				var s = tkText(tkNext);
				var l = s.length - 2;
				item.strSpeaker = s.substr(0, l).trim();
				break;
			case Tok.exStart:
				item.a_conditions.push(parseExpression());
				break;
			}
		}
		//console.log('Indentation: ', item.a_varText, item.intIndent);
		if(item.a_varText.length || item.a_conditions.length){
			if(item.intIndent > indent) {
				var l = psParent.a_psChildren.length - 1;
				if(l >= 0) {
					psParent = psParent.a_psChildren[l];
				}
			}
			else while(item.intIndent <= psParent.intIndent && psParent.psParent) {
				psParent = psParent.psParent;
			}
			psParent.a_psChildren.push(item);
			item.psParent = psParent;
			intLine++;
			indent = item.intIndent;
		}
	}

	return psRoot;
}

// Dictionary of integers to finalized DialogItems (prefix: dia)
function flatten(psParse) {
	var dc_int_dialog = {};

	function flatten_recurse(psParse) {
		var intPrev = -1;
		for(let i = 0; i < psParse.a_psChildren.length; i++) {
			var psChild = psParse.a_psChildren[i];
			psChild.strSpeaker = psChild.strSpeaker || psParse.strSpeaker;
			var diaNode = {
				intNext:-1,
				intParent: psParse.intLine,
				intChild:-1,
				a_varText: psChild.a_varText,
				a_conditions: psChild.a_conditions,
				strSpeaker: psChild.strSpeaker
			};

			dc_int_dialog[psChild.intLine] = diaNode;

			if(intPrev >= 0) {
				dc_int_dialog[intPrev].intNext = psChild.intLine;
			}
			intPrev = psChild.intLine;

			if(psChild.a_psChildren.length > 0) {
				diaNode.intChild = psChild.a_psChildren[0].intLine;
				flatten_recurse(psChild);
			}
		}
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