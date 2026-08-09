(function () {
  'use strict';

  var FEEDBACK_DURATION_MS = 2000;
  var SERVER_ADDRESS_ID = 'server-address';
  var COPY_BUTTON_ID = 'copy-btn';
  var FEEDBACK_CLASS = 'copy-success';

  function getServerAddress() {
    var addressElement = document.getElementById(SERVER_ADDRESS_ID);
    if (addressElement) {
      return addressElement.textContent.trim();
    }
    return '';
  }

  function showFeedback(button) {
    var originalText = button.textContent;
    button.textContent = 'Copiado!';
    button.classList.add(FEEDBACK_CLASS);
    button.disabled = true;

    setTimeout(function () {
      button.textContent = originalText;
      button.classList.remove(FEEDBACK_CLASS);
      button.disabled = false;
    }, FEEDBACK_DURATION_MS);
  }

  function fallbackCopy(text) {
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'absolute';
    textarea.style.left = '-9999px';
    document.body.appendChild(textarea);
    textarea.select();

    var success = false;
    try {
      success = document.execCommand('copy');
    } catch (err) {
      success = false;
    }

    document.body.removeChild(textarea);
    return success;
  }

  function copyToClipboard(text, button) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        showFeedback(button);
      }).catch(function () {
        if (fallbackCopy(text)) {
          showFeedback(button);
        }
      });
    } else {
      if (fallbackCopy(text)) {
        showFeedback(button);
      }
    }
  }

  function init() {
    var copyButton = document.getElementById(COPY_BUTTON_ID);
    if (!copyButton) {
      return;
    }

    copyButton.addEventListener('click', function () {
      var address = getServerAddress();
      if (address) {
        copyToClipboard(address, copyButton);
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
