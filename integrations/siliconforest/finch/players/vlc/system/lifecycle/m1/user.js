// SPDX-License-Identifier: MIT
// THEME: my own Firefox profile for pictures: no first-run pages or bars
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("termsofuse.bypassNotification", true);
user_pref("browser.preonboarding.enabled", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.uitour.enabled", false);
// DEMO additions
user_pref("media.autoplay.default", 0);
user_pref("browser.translations.automaticallyPopup", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("app.update.auto", false);
user_pref("browser.search.suggest.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("identity.fxaccounts.toolbar.enabled", false);
user_pref("browser.vpn_promo.enabled", false);
// SYSINSTALL additions: no feature callouts over the test page
user_pref("browser.startup.upgradeDialog.enabled", false);
user_pref("messaging-system.rsexperimentloader.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
