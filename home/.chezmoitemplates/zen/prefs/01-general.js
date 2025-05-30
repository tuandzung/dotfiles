// === GENERAL ===
// Startup
/* Warn when quitting browser */
user_pref("browser.sessionstore.warnOnQuit", true);

// Language and Appearance
/* Set website default colorscheme to dark
 * [SETTING] General->Language and Appearance->Website Appearance */
user_pref("layout.css.prefers-color-scheme.content-override", 0);
/* Set font for languages
 * [SETTING] General->Language and Appearance->Fonts and Colors */
user_pref("font.default.x-western", "sans-serif"); // Change Latin to Sans-serif
user_pref("font.default.x-unicode", "sans-serif"); // Change Latin to Sans-serif
/* Set default font size
 * [SETTING] General->Language and Appearance->Fonts and Colors */
user_pref("font.size.monospace.x-western", 14);
user_pref("font.size.monospace.x-unicode", 14);
user_pref("font.minimum-size.x-western", 14);
user_pref("font.minimum-size.x-unicode", 14);
/* Disable web page's font
 * [SETTING] General->Language and Appearance->Fonts and Colors */
user_pref("browser.display.use_document_fonts", 0);
/* Set preferred language for displaying web pages
 * [SETTING] General->Language and Appearance->Language->Choose your preferred language for displaying pages */
user_pref("intl.accept_languages", "en-US, vi");

// Files and Applications
/* Ask where to save before download
 * [SETTING] General->Files and Applications->Downloads */
user_pref("browser.download.useDownloadDir", false);

// Performance
/* Use recommended performance settings
 * [SETTING] General->Performance->Use recommended performance settings */
user_pref("browser.preferences.defaultPerformanceSettings.enabled", true);

// Browsing
/* Use autoscrolling
 * [SETTING] General->Browsing->Use autoscrolling */
user_pref("general.autoScroll", true);
/* Use smooth scrolling
 * [SETTING] General->Browsing->Use smooth scrolling */
user_pref("general.smoothScroll", true);

// Network Settings
/* Enable DNS over HTTPS
 * 0=Native DNS from network, 1=Reserved, 2=Use DoH before native, 3=Only DoH
 * [SETTING] General->Network Settings->Enable DNS over HTTPS*/
user_pref("network.trr.mode", 2);

// === HOME ===
// Set HOME+NEWWINDOW page
user_pref("browser.startup.homepage", "about:home");

// === SEARCH ===
// Set search region
user_pref("browser.search.region", "VN");

// === PRIVACY & SECURITY ===
// Password
/* Disable saving passwords */
user_pref("signon.rememberSignons", false);

// History
/* Enable browsing and download history
 * [SETTING] Privacy & Security->History->Custom Settings->Remember browsing and download history */
user_pref("places.history.enabled", true);

// === OTHER ===
/* Default bookmark location */
user_pref("browser.bookmarks.defaultLocation", "toolbar");
/* Stop auto add bookmarks from distribution */
user_pref("distribution.gentoo.bookmarksProcessed", true);
user_pref("distribution.archlinux.bookmarksProcessed", true);

/* Enable customChrome.css */
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
/* Enable GPU acceleration */
user_pref("layers.acceleration.force-enabled", true);
/* Enable WebRender to render page faster */
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.enabled", true);
/* Enable transparent */
user_pref("layout.css.backdrop-filter.enabled", true);
/* Allow SVG CSS */
user_pref("svg.context-properties.content.enabled", true);
/* Proton Tooltip */
user_pref("browser.proton.places-tooltip.enabled", true);
/* Compact Mode */
user_pref("browser.compactmode.show", true);
