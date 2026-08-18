"use strict";
// See compiler.js for coding style.
const name = 'np_dialog_display';

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

function appendTextOrElement(elemParent, varMsg) {
	if(varMsg && 'baseURI' in varMsg) {
		elemParent.appendChild(varMsg);
	}
	else {
		appendText(elemParent, String(varMsg));
	}
}

export {addChild, appendText, appendTextOrElement, name};