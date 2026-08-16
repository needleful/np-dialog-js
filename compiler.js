"use strict";
// This is intended to be loaded as a module.
// The code uses Hungarian notation for all variables,
// with the following prefixes:
// str: String, int: Number (as integer), fl: Number(as float)
// b: boolean, rx: Regular Expresion, var: Variadic (multiple types)
// a_X: Array of X, dc_X_Y: Dictionary of X key to Y value
// Other prefixes will be specified with the constructor function.

const name = 'np_dialog_compiler';

const Tok = {
	invalid: 0,
	newLine: 1,
	textPlain: 2,
	comment: 3,
	indent: 4,
	unindent: 5,

	symNarration: 10,
	symSpeaker: 11,
	symLabel: 12,
	symOption: 13,

	markEscape: 20,
	markItalics: 21,
	markBold: 22,
	markStrike: 23,
	markInterpolate:24,

	exStart: 30,
	exEnd: 31,
	exIdentifier: 32,
	exOp: 33,
	exArgSplit: 35,
	exText: 36,
	exRawValue: 37,
	exDynamicVar: 38,
	exEscape: 39
};

let TokNames = {};
for(let k in Tok) {
	TokNames[Tok[k]] = k;
}
Object.freeze(TokNames);

function readableTk(strText, tk) {
	return [strText.substr(tk.intStart, tk.intLength), TokNames[tk.tokType]];
}

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
			return null;
		}
		var start = intC;
		if(bSkipSpace) skipWhiteSpace();
		if(strLower.startsWith(strMatch, intC)) {
			pushTextTk(tokType, strMatch);
			return strMatch;
		}
		else {
			intC = start;
			return null;
		}
	}
	function matchesOneOf(tokType, a_strMatches) {
		if(!isGood()) {
			return null;
		}
		var start = intC;
		for(let i = 0; i < a_strMatches.length; i++) {
			if(findString(tokType, a_strMatches[i], i)) {
				return a_strMatches[i];
			}
		}
		intC = start;
		return null;
	}
	function matchesRegex(tokType, rxMatch, bSkipSpace = true) {
		if(!isGood()) {
			return null;
		}
		var start = intC;
		if(bSkipSpace) skipWhiteSpace();
		let m = strText.substr(intC).match(rxMatch);
		if(m) {
			pushTextTk(tokType, m[0]);
			return m[0];
		}
		else {
			intC = start;
			return null;
		}
	}

	function matchesIdentifer() {
		return matchesRegex(Tok.exIdentifier, /^\p{Alpha}[\p{Alpha}\d_]*\b/u);
	}
	function matchesDynVar() {
		return matchesRegex(Tok.exDynamicVar, /^\$\p{Alpha}[\-'+\p{Alpha}\d_]*\b/u)
	}
	function matchesRawValue() {
		// TODO: a recursive tokenization to allow for nested structures
		return matchesRegex(Tok.exRawValue, /^\#[^\]\|\:]+/);
	}
	function matchesOp() {
		return matchesRegex(Tok.exOp, /^[+\-=/\\|?<>&%$!@:]+/);
	}
	function tokenizeExpression() {
		var intStart = intC;
		// Optional starting operator
		matchesOp();
		// Required starting identifier or sub-expression
		var bValid = false;
		if(matchesString(Tok.exStart, '[')) {
			tokenizeExpression();
			bValid = true;
		}
		else {
			bValid = (
				matchesIdentifer()
				|| matchesDynVar()
				|| matchesRawValue()
			);
		}
		if(!bValid) {
			if(matchesString(Tok.exStart, '[')) {
			}
			else {
				pushErrorTk('Could not parse expression: no starting identifier', '', intStart);
			}
		}
		// Function head
		while(isGood()) {
			if(matchesIdentifer()) continue;
			if(matchesOp())
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
				|| matchesDynVar()
				|| matchesRawValue()
				|| matchesRegex(Tok.exText, /^[^\[\]\\|]+/)
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

	function tokenizeLabel() {
		if(!matchesIdentifer()){
			pushErrorTk('TK: Expected identifier after {:} for label.', matchesRegex(Tok.invalid, /^./));
			return;
		}
	}

	// 0: start of line (allows narration, reply, and speaker markings. Checks for indentation)
	// 1: control flow (allows conditions)
	// 2: text and interpolation only
	var intState = 0;
	var indentation = 0;
	while(isGood()){
		if(intState == 0) {
			var intSkipped = skipWhiteSpace();
			if(intSkipped > indentation) {
				pushTk(Tok.indent, intSkipped, intC - intSkipped);
			}
			else if(intSkipped < indentation) {
				pushTk(Tok.unindent, intSkipped, intC - intSkipped);
			}
			indentation = intSkipped;
			intState = 1;
			continue;
		}
		if(intState < 2) {
			if(matchesString(Tok.symLabel, ':')) {
				tokenizeLabel();
				continue;
			}
			if(matchesString(Tok.symNarration, '*')
				|| matchesRegex(Tok.symSpeaker, /^[^\s-[\]]+\s*--/)
				|| matchesRegex(Tok.comment, /^\/\/[^\n]*/)
				|| matchesString(Tok.symOption, '>')
			) {
				intState = 2;
				continue;
			}
		}
		if(intState < 3) {
			if(matchesString(Tok.exStart, '[')) {
				tokenizeExpression();
				continue;
			}
		}
		else if(matchesString(Tok.markInterpolate, '[')) {
			tokenizeExpression();
			continue;
		}
		if(matchesString(Tok.markEscape, '\\')) {
			if(isGood()) { 
				pushTk(Tok.textPlain, 1);
			}
			continue;
		}
		if(matchesString(Tok.markItalics, '/')
			|| matchesString(Tok.markBold, '_')
			|| matchesString(Tok.markStrike, '~')
			|| matchesString(Tok.textPlain, '#')
			|| matchesRegex(Tok.textPlain, /^[^\n\/\\_#\[\]]+/, false)
		) {
			intState = 3;
			continue;
		}
		if(matchesRegex(Tok.newLine, /^\n+/)) {
			intState = 0;
			continue;
		}
		matchesRegex(Tok.invalid, /^./);
	}
	return a_tkResult;
}

const ItemType = {
	message: 0,
	narration: 1,
	option: 2
};
const ItemTypeNames = {
	0: 'message',
	1: 'narration',
	2: 'option'
};

const OpFlags = {
	prefix: 1,
	postfix: 2,
	infix: 4
};
let OpFlagNames = {
	1: 'prefix',
	2: 'postfix',
	3: 'prefix & postfix',
	4: 'infix',
	5: 'prefix & infix',
	6: 'postfix & infix',
	7: 'prefix, postfix & infix'
};

const Operators = {
	'!': OpFlags.prefix,
	'?': OpFlags.postfix,
	':': OpFlags.infix,
	':=': OpFlags.infix,
	'=': OpFlags.infix,
	'>': OpFlags.infix,
	'<': OpFlags.infix,
	'<=': OpFlags.infix,
	'>=': OpFlags.infix,
	'!=': OpFlags.infix,
	'+=': OpFlags.infix,
	'-=': OpFlags.infix,
	'/=': OpFlags.infix,
	'*=': OpFlags.infix,
	'%': OpFlags.infix,
	'%=': OpFlags.infix,
	'&': OpFlags.infix,
	'&=': OpFlags.infix,
	'&&': OpFlags.infix,
	'&&=': OpFlags.infix,
	'|= ': OpFlags.infix,
	'||= ': OpFlags.infix,
	'+': OpFlags.infix | OpFlags.prefix,
	'-': OpFlags.infix | OpFlags.prefix,
	'*': OpFlags.infix,
	'/': OpFlags.infix,
	'|': OpFlags.infix,
	'||': OpFlags.infix,
	'@': OpFlags.infix,
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
		intLine: -1,
		a_errors: [],
	};
	function pushTkError(strMsg, tk) {
		var tkReadable = readableTk(strText, tk);
		console.error(strMsg, tkReadable);
		psRoot.a_errors.push({
			strMsg: strMsg,
			tkSource: tk,
			tkReadable: tkReadable
		});
	}

	function parseExpression() {
		var exResult = {
			a_head: [],
			a_tail: [],
			strStartOp: undefined,
			strEndOp: undefined,
		}
		function validateOp(tkOp, opflagReq) {
			var strOp = tkText(tkOp);
			if(!(strOp in Operators)) {
				pushTkError(`Unknown operator: {${strOp}}`, tk);
				return;
			}
			var flags = Operators[strOp];
			if((opflagReq & flags) != opflagReq) {
				pushTkError(
					`Operator {${strOp}} was not the required type: ${OpFlagNames[opflagReq]}. Actual: ${OpFlagNames[flags]}`,
					tkOp
				);
			}
		}
		var head = true;
		if(peek().type == Tok.exOp) {
			var leadOp = pop();
			validateOp(leadOp, OpFlags.prefix);
		}
		var tkOp;
		function validate() {
			if(exResult.strEndOp) {
				validateOp(tkOp, exResult.a_tail.length? OpFlags.infix : OpFlags.postfix);
			}
			return exResult;
		}
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
				return validate();
			case Tok.exStart:
				exResult.a_head.push(parseExpression());
				break;
			case Tok.exOp:
				tkOp = tk;
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
			case Tok.exText:
				exResult.a_tail.push(tkText(tk));
				break;
			case Tok.exEnd:
				return validate();
			case Tok.exStart:
				exResult.a_tail.push(parseExpression());
				break;
			case Tok.exArgSplit:
				break;
			default:
				console.error('Invalid argument: ', tkText(tk), tk)
				return validate();
			}
		}
		return validate();
	}
	function parseLabel() {
		var label = {
			strFunctor: undefined,
			a_varArgs: [],
			a_conditions: [],
			strBlockName: undefined, 
		};
		var s = peek();
		if(s.tokType != Tok.exIdentifier) {
			pushTkError('PS: Expected an identifier after {:}', s);
		}
		else {
			pop();
			label.strFunctor = tkText(s);
		}
		var nl = peek();
		if(nl.tokType != Tok.newLine) {
			pushTkError('PS: Expected a newline after label declaration', s);
		}
		else {
			pop();
		}
		return label;
	}
	var psParent = psRoot;
	var intLine = 0;
	var indent = 0;
	var a_labels = [];
	while(isGood()) {
		var item = {
			type: ItemType.message,
			// String, interpolation, or tag
			a_varText: [],
			a_conditions: [],
			strSpeaker: '',
			a_psChildren: [],
			a_labels: [],
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
			case Tok.symOption:
				item.type = ItemType.option;
				break;
			case Tok.symSpeaker:
				var s = tkText(tkNext);
				var l = s.length - 2;
				item.strSpeaker = s.substr(0, l).trim();
				break;
			case Tok.symLabel:
				a_labels.push(parseLabel());
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
			case Tok.markInterpolate:
				item.a_varText.push({expInterp: parseExpression()});
				break;
			case Tok.indent:
			case Tok.unindent:
				item.intIndent = tkNext.intLength;
				break;
			case Tok.exStart:
				item.a_conditions.push(parseExpression());
				break;
			}
		}

		if(item.a_varText.length || item.a_conditions.length){
			item.a_labels = a_labels;
			a_labels = [];
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

// A dialog sequence (prefix: seq)
function flatten(psParse) {
	var dc_int_dialog = {};
	var dc_str_labels= {};

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
				strSpeaker: psChild.strSpeaker,
				type: psChild.type
			};
			for(let l = 0; l < psChild.a_labels.length; l++) {
				var label = psChild.a_labels[l];
				dc_str_labels[label.strFunctor] = psChild.intLine;
			}

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
	return {
		dc_int_dialog: dc_int_dialog,
		dc_str_labels: dc_str_labels,
		intStart: 0
	};
}

// Returns a dictionary
/*	{
		dc_str_labels,
		dc_int_dialog,
		intStart
	}
	prefix: seq
*/
function compile(strText) {
	var a_tkTokens = tokenize(strText);
	var readableTokens = [];
	for(var t = 0; t < a_tkTokens.length; t++){
		var tk = a_tkTokens[t];
		readableTokens.push(readableTk(strText, tk));
	}
	console.log(readableTokens);
	var psParse = parse(strText, a_tkTokens);
	for(var i = 0; i < psParse.a_errors.length; i++) {
		var err = psParse.a_errors[i];
		console.error(err.strMsg);
	}
	var seqResult = flatten(psParse);
	return seqResult;
}

function quote(strText) {
	return '"' + strText.replaceAll('"', '\\"') + '"';
}

const OpRemap = {
	':=': '=',
	'=': '=='
};

// Operators that can be chained
const OpChained = [
	'+',
	'=',
	'-',
	'/',
	'&&',
	'&',
	'|',
	'||',
	'%'
];

// Operators that are NOT just another operator plus assignment
// Which is assumed the default for any multi-char op ending in '=' 
const OpUniqueEq = [
	'!=',
	'==',
	'>=',
	'<=',
];

// Requires rewriting `x == y == z` as `x == y && x == z`
const OpBoolChain = [
	'==',
	'!=',
	'>',
	'<',
];

function contains(array, value) {
	return array.indexOf(value) >= 0;
}

function opToJS(strOp, strHead, a_strTail) {
	if(strOp == ':') {
		return strHead + `(${a_strTail.join(', ')})`;
	}
	if(strOp == '@') {
		return strHead + `[${a_strTail.join(', ')}]`;
	}
	if(strOp in OpRemap) {
		strOp = OpRemap[strOp];
	}
	var trueOp = strOp;
	// Strip op-assignment
	if(strOp.length > 1 && strOp.endsWith('=') && !contains(OpUniqueEq, strOp)) {
		strOp = strOp.substr(0, strOp.length - 1);
	}
	var strTailSub = '';
	var strStart = strHead + trueOp;
	if(contains(OpChained, strOp)) {
		strTailSub = a_strTail.join(' ' + strOp + ' ');
	}
	else if(contains(OpBoolChain, strOp)) {
		// Much simpler case
		if(a_strTail.length == 1) {
			strTailSub = a_strTail[0];
		}
		else {
			// Assign to a temporary variable
			strStart += `(__temp = (${strHead})), __temp ` + trueOp
			var s = [];
			for(let t = 0; t < a_strTail.length; t++) {
				s.push(`(__temp ${strOp} ${a_strTail[t]})`);
			}
			strTailSub = s.join(' && ')
		}
	}
	return strStart + strTailSub;
}

function expToJS(seqInput, exp) {
	var a_strHead = [];
	for(let h = 0; h < exp.a_head.length; h++) {
		var expData = exp.a_head[h];
		if(typeof(expData) == 'string') {
			if(!a_strHead.length) {
				a_strHead.push('ctx');
			}
			a_strHead.push(expData);
		}
		else if('strVar' in expData) {
			if(!a_strHead.length) {
				a_strHead.push('ctx');
			}
			else {
				console.error('Cannot use dynamic variables ($var) as a field.');
			}
			a_strHead.push(`_vars[${quote(expData.strVar)}]`);
		}
		else if('strRaw' in expData) {
			a_strHead.push(`(${expData.strRaw.substr(1)})`);
		}
		else if('a_head' in expData) {
			a_strHead.push(`(${expToJS(seqInput, expData)})`);
		}
	}
	var a_strTail = [];
	for(let t = 0; t < exp.a_tail.length; t++) {
		var expTail = exp.a_tail[t];
		if(typeof(expTail) == 'string') {
			a_strTail.push(quote(expTail));
		}
		else if('strVar' in expTail) {
			a_strTail.push(`ctx._vars[${quote(expTail.strVar)}]`);
		}
		else if('strRaw' in expTail) {
			a_strTail.push(`(${expTail.strRaw.substr(1)})`);
		}
		else if('a_head' in expTail) {
			a_strTail.push(`(${expToJS(seqInput, expTail)})`);
		}
	}
	var strCode = a_strHead.join('.');
	if(!a_strTail.length) {
		// Only postfix operator is {?},
		// which turns a function call into a variable access
		if(!exp.strEndOp) {
			strCode += '()';
		}
	}
	else if(exp.strEndOp) {
		// Infix Operators
		var strOp = exp.strEndOp;
		strCode = opToJS(strOp, strCode, a_strTail)
	}

	// Prefix operator has highest precedence
	if(exp.strStartOp == '+') {
		return `math.abs(${strCode})`;
	}
	else if(exp.strStartOp) {
		return `${exp.strStartOp}(${strCode})`;
	}
	return strCode;
}

// A list of dialog options turned into javascript
function textToJs(seqInput, dialog) {
	if (!dialog.a_varText.length){
		return 'null';
	}
	var cls = 'dia-' + ItemTypeNames[dialog.type];

	var a_strCode = [
		`(e) => { e.classList.add('${cls}')`
	];
	function compileElement() {

	}
	var tagStack = [];
	var workingElemDefined = false;
	for(let i = 0; i < dialog.a_varText.length; i++) {
		var txt = dialog.a_varText[i];
		if(typeof(txt) == 'string') {
			a_strCode.push(`datxt(e, ${quote(txt)})`);
			continue;
		}
		else if('tagStart' in txt) {
			tagStack.push(txt.tagStart);
			if(!workingElemDefined) {
				a_strCode.push(`var _we = document.createElement('${txt.tagStart}')`);
				workingElemDefined = true;
			}
			else {
				a_strCode.push(`_we = document.createElement('${txt.tagStart}')`);
			}
			a_strCode.push('e.appendChild(_we); e = _we');
		}
		else if('tagEnd' in txt) {
			var tag = txt.tagEnd;
			var realTag = tagStack.pop();
			if(tag != realTag) {
				console.error('Unexpected end tag: ', tag);
			}
			a_strCode.push(`e = e.parentElement`);
		}
		else if('expInterp' in txt) {
			a_strCode.push(`datxt(e, String(${expToJS(seqInput, txt.expInterp)}))`)
		}
		else {
			a_strCode.push('//todo: '+ JSON.stringify(txt));
		}
	}
	a_strCode.push('}')
	return a_strCode.join(';\n');
}

function condToJs(seqInput, dialog) {
	if(!dialog.a_conditions.length) {
		return 'always';
	}
	var a_strCode = ['(ctx) => '];
	var a_strConds = []
	for(let c = 0; c < dialog.a_conditions.length; c++) {
		var cond = dialog.a_conditions[c];
		a_strConds.push(`(${expToJS(seqInput, cond)})`);
	}
	a_strCode.push(a_strConds.join(' && '));
	return a_strCode.join('');
}

// Returns javascript source code.
function toJS(seqInput, strName) {
	var a_strCode = [strName, ' = {',
		'dc_str_labels: {'
	];
	for(var label in seqInput.dc_str_labels) {
		var intVal = seqInput.dc_str_labels[label];
		a_strCode.push(`\t${quote(label)}: ${intVal},`);
	}
	a_strCode.push('},')

	for(var intIdx in seqInput.dc_int_dialog) {
		var dialog = seqInput.dc_int_dialog[intIdx];
		a_strCode.push(`${intIdx}: {`);
		a_strCode.push(
			`\tintNext: ${dialog.intNext}, intChild:${dialog.intChild}, intParent:${dialog.intParent},`
		);
		a_strCode.push(`\taddText: ${textToJs(seqInput, dialog)},`);
		a_strCode.push(`\tcanEnter: ${condToJs(seqInput, dialog)},`)
		a_strCode.push('},');
	}

	a_strCode.push('}');
	return a_strCode.join('\n');
}

export {name, compile, toJS, ItemType};