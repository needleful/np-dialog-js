"use strict";
// See compiler.js for coding style.
const name = 'np_dialog_display';

import * as Dialog from './compiler.js';

function addChild(elemParent, strMessage = '', strElemType='p') {
	var elemNew = document.createElement(strElemType);
	elemParent.appendChild(elemNew);
	elemNew.innerText = strMessage;
	return elemNew;
}

function appendText(elemParent, strMessage) {
	var tElem = document.createTextNode(strMessage);
	elemParent.appendChild(tElem);
	return tElem;
}

// Get an array of HTML elements from the item's message
function shapeText(a_varText) {
	var a_elemResult = [];
	// If there's a parent, we're adding these into a nested item.
	var elemParent = null;
	function insert(elem) {
		if(elemParent) {
			elemParent.appendChild(elem);
		}
		else {
			a_elemResult.push(elem);
		}
		return elem;
	}
	for(let intT = 0; intT < a_varText.length; intT++) {
		var varText = a_varText[intT];
		if(typeof(varText) === 'string') {
			insert(document.createTextNode(varText));
		}
		else if('tagStart' in varText) {
			elemParent = insert(document.createElement(varText.tagStart));
		}
		else if('tagEnd' in varText) {
			if(!elemParent) {
				console.error('Unexpected end tag: ', varText.tagEnd);
				continue;
			}
			var tagReal = elemParent.tagName.toLowerCase();
			var tagClosed = varText.tagEnd.toLowerCase();
			if(tagReal != tagClosed) {
				console.error('Mismatched tags: ', tagClosed, tagReal);
			}
			elemParent = elemParent.parentElement;
		}
		// else if('expInterp' in varText) {
		// }
		else {
			var elemUnknown = document.createElement('code');
			elemUnknown.innerText = JSON.stringify(varText);
			insert(elemUnknown);
		}
	}
	return a_elemResult;
}

function displayDebug(elemParent, seqDialog) {
	for(let strKey in seqDialog.dc_str_labels) {
		addChild(elemParent, `${strKey}: ${seqDialog.dc_str_labels[strKey]}`)
	}
	for(let intIndex in seqDialog.dc_int_dialog) {
		var diaItem = seqDialog.dc_int_dialog[intIndex];
		if(!diaItem.a_varText.length){
			continue;
		}
		var elemMsg = addChild(elemParent);
		if(diaItem.type == Dialog.ItemType.message) {
			addChild(elemMsg, diaItem.strSpeaker || '<default>', 'i');
			appendText(elemMsg, ': ');
		}
		else if(diaItem.type == Dialog.ItemType.narration) {
			appendText(elemMsg, '* ');
		}
		else if(diaItem.type == Dialog.ItemType.option) {
			appendText(elemMsg, '> ');
		}
		else {
			appendText(elemMsg, '<?>');
		}
		var a_elemText = shapeText(diaItem.a_varText);
		for(let i = 0; i < a_elemText.length; i++) {
			elemMsg.appendChild(a_elemText[i]);
		}
	}
}

export {displayDebug, addChild, appendText, name};