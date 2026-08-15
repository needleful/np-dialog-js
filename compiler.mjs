"use strict";
// This is intended to be loaded as a module.
// The code uses Hungarian notation for all variables,
// with the following prefixes:
// str: String, int: Number (as integer), fl: Number(as float)
// b: boolean, rx: Regular Expresion, var: Variadic (multiple types)
// a_X: Array of X
// Other prefixes will be specified with the constructor function.

const name = 'np_dialog';

const Tok {
	invalid: 0,
	newLine: 1,
	textPlain: 2,
	comment: 3,

	symNarration: 10,
	symSpeaker: 11,

	markEscape: 20,
	markItalics: 21,
	markBold: 22,
};

// Creates an array of Tokens (prefix: tk)
function tokenize(strText) {
	let intC = 0;
	let a_tkResult = [];
	const strLower = strText.toLowerCase();
	function pushTextTk(tokType, intSubType, strText) {
		a_tkResult.push({
			tokType:tokType,
			varInfo: intSubType,
			intStart: intC,
			intLength: strText.length
		});
		intC += strText.length;
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
		let m = strText.substr(intC).match(/^\s+/);
		if(m) {
			intC += m[0].length;
		}
	}
	function matchesString(tokType, strMatch, intSubType = 0, bSkipSpace = true) {
		if(!isGood()) {
			return false;
		}
		if(bSkipSpace) skipWhiteSpace();
		if(strLower.startsWith(strMatch, intC)) {
			pushTextTk(tokType, intSubType, strMatch);
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
	function matchesRegex(tokType, rxMatch, varInfo = 0, bSkipSpace = true) {
		if(!isGood()) {
			return false;
		}
		if(bSkipSpace) skipWhiteSpace();
		let m = text.substr(intC).match(rxMatch);
		if(m) {
			pushTextTk(tokType, varInfo, m[0]);
			return true;
		}
		else {
			return false;
		}
	}

	// Some symbols are different at the start of a line.
	var newLine = true;
	while(isGood()){
		if(newLine) {
			if(matchesString(Tok.symNarration, '*')){

			}
		}
	}
	return a_tkResult;
}

// Returns a ParseTree (prefix: ps)
function parse(a_tkTokens) {

}

// Returns an array of DialogItems (prefix: dia)
function analyze(psParseTree) {

}

// Returns DialogItems from text
function compile(strText) {
	var a_tkTokens = tokenize(strText);
	var psParseTree = parse(a_tkTokens);
	var sqSequence = analyze(psParseTree); 
	return a_diaSequence;
}

export {name, compile};