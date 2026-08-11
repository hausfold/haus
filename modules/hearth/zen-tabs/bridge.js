// The browser half of the tab bridge: publish the tab list, act on a focus.
//
// WHY THIS EXISTS. macOS's now-playing session — the thing the media pill reads
// — carries no URL and no tab, only a title and a bundle id. Safari and the
// Chromium browsers at least hand their tab list to AppleScript, so the bar can
// look the tab up. Firefox and its forks hand out nothing at all: no AppleScript
// dictionary, and no accessibility tree either (verified against a live Zen —
// the tab strip is absent from the AX tree even with Firefox's a11y engine
// forced on via AXEnhancedUserInterface). The only thing inside the browser that
// can answer "which tab is this?" is an extension, so: an extension.
//
// MANIFEST V2, deliberately. The whole design rests on a native-messaging port
// that stays connected for the browser's whole life — that port is what keeps
// the bar's view of the tabs current, and what carries a focus command back the
// other way. An MV2 persistent background page simply stays up. Under MV3 the
// same code lives on an event page whose lifetime is the browser's to end, and
// while an open Port currently keeps a Firefox event page alive, resting a
// permanently-connected socket on that guarantee is resting it on an
// implementation detail. Zen is Firefox 153 and MV2 is still first-class there.

const HOST = "co.hausfold.zentabs";

// The one thing this file owes the other half: a debounce. Loading a page fires
// onUpdated several times (title, then url, then favicon), and a snapshot per
// event would push a few hundred tabs through the pipe several times a second
// for as long as you browse. Nothing downstream needs sub-second freshness — the
// consumer is a click on a bar pill.
const SETTLE_MS = 300;

let port = null;
let pending = null;
let backoff = 1000;

function snapshot() {
  if (!port) return;
  browser.tabs
    .query({})
    .then((tabs) => {
      if (!port) return;
      port.postMessage({
        type: "tabs",
        tabs: tabs.map((t) => ({
          id: t.id,
          windowId: t.windowId,
          title: t.title || "",
          url: t.url || "",
          audible: !!t.audible,
          active: !!t.active,
        })),
      });
    })
    .catch(() => {});
}

function schedule() {
  if (pending) return;
  pending = setTimeout(() => {
    pending = null;
    snapshot();
  }, SETTLE_MS);
}

function connect() {
  try {
    port = browser.runtime.connectNative(HOST);
  } catch (e) {
    // No host manifest installed, or it names a path that isn't there. Nothing
    // to retry against — a rebuild is what fixes it, and a rebuild restarts
    // nothing here, so this is genuinely the end of the road for this session.
    port = null;
    return;
  }

  port.onMessage.addListener((msg) => {
    if (!msg || msg.cmd !== "focus" || typeof msg.tabId !== "number") return;
    // Both halves matter and they are not the same thing: `tabs.update` makes
    // the tab current WITHIN its window, `windows.update` brings that window to
    // the front. Doing only the first switches a tab in a window you can't see.
    browser.tabs
      .update(msg.tabId, { active: true })
      .then((t) => browser.windows.update(t.windowId, { focused: true }))
      .catch(() => {});
  });

  port.onDisconnect.addListener(() => {
    port = null;
    // The host dies with the browser, so a disconnect while we're still running
    // means it crashed or was replaced by a rebuild. Back off rather than spin:
    // a host that fails to start fails to start every time.
    setTimeout(connect, backoff);
    backoff = Math.min(backoff * 2, 60000);
  });

  backoff = 1000;
  snapshot();
}

browser.tabs.onCreated.addListener(schedule);
browser.tabs.onRemoved.addListener(schedule);
browser.tabs.onActivated.addListener(schedule);
browser.tabs.onAttached.addListener(schedule);
browser.tabs.onDetached.addListener(schedule);
// Filtered at the source rather than in `schedule`: onUpdated is the loudest
// event in the API (it fires for favicons, load state, mute state, discarding)
// and only these three change anything the bar can act on.
browser.tabs.onUpdated.addListener(schedule, {
  properties: ["title", "url", "audible"],
});

connect();
