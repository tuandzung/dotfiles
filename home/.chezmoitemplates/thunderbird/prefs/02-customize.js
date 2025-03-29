user_pref("mailnews.start_page.url", "about:about");
/* Set font for languages
 * [SETTING] General->Language and Appearance->Fonts and Colors */
user_pref("font.default.x-western", "sans-serif"); // Change Latin to Sans-serif
user_pref("font.default.x-unicode", "sans-serif"); // Change Latin to Sans-serif
user_pref("font.name.monospace.x-western", "Tepiosevka");
user_pref("font.name.sans-serif.x-western", "Tepiosevka");
user_pref("font.name.serif.x-western", "Tepiosevka");
/* Set default font size
 * [SETTING] General->Language and Appearance->Fonts and Colors */
user_pref("font.size.monospace.x-western", 14);
user_pref("font.size.monospace.x-unicode", 14);
user_pref("font.minimum-size.x-western", 14);
user_pref("font.minimum-size.x-unicode", 14);
/* Disable web page's font
 * [SETTING] General->Language and Appearance->Fonts and Colors */
user_pref("browser.display.use_document_fonts", 0);
/* Disable fission */
user_pref("fission.autostart", false);
user_pref("dom.ipc.processCount.webIsolated", 1);
user_pref("dom.ipc.processCount", 1);
