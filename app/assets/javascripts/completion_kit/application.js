document.addEventListener("turbo:load", function() {
  document.querySelectorAll("[data-local-time]").forEach(function(el) {
    var d = new Date(el.getAttribute("datetime"));
    el.textContent = d.toLocaleString(undefined, {year:"numeric",month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"});
  });
  ckTickRelativeTimes();
  ckAutoFocusFirstError();
  if (ckDiscoveringInDom()) ckStartDiscoveryPolling(0);
});

document.addEventListener("turbo:render", ckAutoFocusFirstError);

document.addEventListener("input", function(e) {
  if (!e.target || e.target.id !== "tag_name") return;
  var text = document.getElementById("tag-pill-text");
  if (!text) return;
  var v = e.target.value.trim().toLowerCase();
  text.textContent = v.length ? v : (text.dataset.placeholder || "");
});

function ckAutoFocusFirstError() {
  var fieldSelector = "input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=reset]):not([type=file]), textarea, select";
  var marker = document.querySelector("form .ck-flash--alert, form [aria-invalid='true'], form .ck-field-error");

  var target;
  if (marker) {
    var form = marker.closest("form");
    target = form && (form.querySelector("[aria-invalid='true']") || form.querySelector(fieldSelector));
  } else if (/\/new(\/|$)/.test(window.location.pathname)) {
    target = document.querySelector("form " + fieldSelector);
  }

  if (!target || typeof target.focus !== "function") return;
  target.focus({ preventScroll: false });
  if (typeof target.setSelectionRange === "function" && typeof target.value === "string") {
    try { target.setSelectionRange(target.value.length, target.value.length); } catch (e) {}
  }
}

function ckRelativeTime(then) {
  var seconds = Math.round((Date.now() - then.getTime()) / 1000);
  if (seconds < 60) return "just now";
  var minutes = Math.round(seconds / 60);
  if (minutes < 60) return (minutes === 1 ? "1 minute" : minutes + " minutes") + " ago";
  var hours = Math.round(minutes / 60);
  if (hours < 24) return (hours === 1 ? "about 1 hour" : "about " + hours + " hours") + " ago";
  var days = Math.round(hours / 24);
  if (days < 30) return (days === 1 ? "1 day" : days + " days") + " ago";
  var months = Math.round(days / 30);
  if (months < 12) return (months === 1 ? "about 1 month" : "about " + months + " months") + " ago";
  var years = Math.round(days / 365);
  return (years === 1 ? "about 1 year" : "about " + years + " years") + " ago";
}

function ckRelativeTimeCompact(then) {
  var seconds = Math.round((Date.now() - then.getTime()) / 1000);
  if (seconds < 60) return "just now";
  var minutes = Math.round(seconds / 60);
  if (minutes < 60) return minutes + "m ago";
  var hours = Math.round(minutes / 60);
  if (hours < 24) return hours + "h ago";
  var days = Math.round(hours / 24);
  if (days < 30) return days + "d ago";
  var months = Math.round(days / 30);
  if (months < 12) return months + "mo ago";
  var years = Math.round(days / 365);
  return years + "y ago";
}

function ckTickRelativeTimes() {
  document.querySelectorAll("[data-relative-time]").forEach(function(el) {
    var then = new Date(el.getAttribute("datetime"));
    if (isNaN(then.getTime())) return;
    var verbose = el.getAttribute("data-relative-time") === "verbose";
    el.textContent = verbose ? ckRelativeTime(then) : ckRelativeTimeCompact(then);
    el.setAttribute("title", then.toLocaleString());
  });
}

if (!window.ckRelativeTimeInterval) {
  window.ckRelativeTimeInterval = setInterval(ckTickRelativeTimes, 30000);
}
document.addEventListener("turbo:before-stream-render", function() {
  requestAnimationFrame(ckTickRelativeTimes);
});

var ckCsvHoverTimer = null;
var ckCsvHoverRow = null;
var ckHoverRowSelector = ".ck-csv-table tbody tr, .ck-responses-table tbody tr";
function ckHoverExpandClass(row) {
  return row.closest(".ck-responses-table") ? "ck-response-row--expanded" : "ck-csv-row--expanded";
}
document.addEventListener("mouseover", function(e) {
  var row = e.target.closest && e.target.closest(ckHoverRowSelector);
  if (!row || row === ckCsvHoverRow) return;
  if (ckCsvHoverRow) ckCsvHoverRow.classList.remove("ck-csv-row--expanded", "ck-response-row--expanded");
  ckCsvHoverRow = row;
  clearTimeout(ckCsvHoverTimer);
  ckCsvHoverTimer = setTimeout(function() {
    if (ckCsvHoverRow === row) row.classList.add(ckHoverExpandClass(row));
  }, 350);
});
document.addEventListener("mouseout", function(e) {
  var row = e.target.closest && e.target.closest(ckHoverRowSelector);
  if (!row) return;
  var related = e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest(ckHoverRowSelector);
  if (related === row) return;
  clearTimeout(ckCsvHoverTimer);
  row.classList.remove("ck-csv-row--expanded", "ck-response-row--expanded");
  if (ckCsvHoverRow === row) ckCsvHoverRow = null;
});

var ckRefreshing = false;
function ckSetRefreshButtonsBusy(busy) {
  document.querySelectorAll('.ck-icon-btn[title="Refresh models"]').forEach(function(btn) {
    btn.classList.toggle('ck-icon-btn--spinning', busy);
    btn.disabled = busy;
  });
}
function ckRefreshUrl() {
  var el = document.querySelector("[data-ck-refresh-url]");
  return el ? el.getAttribute("data-ck-refresh-url") : null;
}
function ckRefreshModels() {
  if (ckRefreshing) return;
  var url = ckRefreshUrl();
  if (!url) return;
  ckRefreshing = true;
  ckSetRefreshButtonsBusy(true);
  ckUpdateRefreshProgress();
  var csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute("content");
  fetch(url, {
    method: "POST",
    headers: { "X-CSRF-Token": csrfToken }
  });
  ckStartDiscoveryPolling(8000);
}

var ckDiscoveryPollTimer = null;
var ckDiscoveryPollUntil = 0;

function ckDiscoveringInDom() {
  return !!document.querySelector('[id^="discovery_status_"] .ck-discovery-bar:not(.ck-discovery-bar--failed):not(.ck-discovery-bar--completed)');
}

function ckStatusesUrl() {
  var el = document.querySelector("[data-ck-statuses-url]");
  return el ? el.getAttribute("data-ck-statuses-url") : null;
}

function ckPollDiscoveryOnce() {
  var url = ckStatusesUrl();
  if (!url) return;
  fetch(url, { headers: { "Accept": "text/vnd.turbo-stream.html" } })
    .then(function(r) { return r.ok ? r.text() : null; })
    .then(function(html) {
      if (html && window.Turbo && window.Turbo.renderStreamMessage) window.Turbo.renderStreamMessage(html);
    })
    .catch(function() {});
}

function ckStartDiscoveryPolling(graceMs) {
  if (!ckStatusesUrl()) return;
  ckDiscoveryPollUntil = Date.now() + (graceMs || 0);
  if (ckDiscoveryPollTimer) return;
  ckPollDiscoveryOnce();
  ckDiscoveryPollTimer = setInterval(function() {
    ckPollDiscoveryOnce();
    if (!ckDiscoveringInDom() && Date.now() > ckDiscoveryPollUntil) {
      clearInterval(ckDiscoveryPollTimer);
      ckDiscoveryPollTimer = null;
    }
  }, 1500);
}

function ckUpdateRefreshProgress() {
  var status = document.getElementById('refresh-status');
  if (!status) return;
  var carriers = document.querySelectorAll('[data-refresh-progress-carriers] [id^="discovery_status_"]');
  var totalCurrent = 0, totalTotal = 0, anyDiscovering = false;
  carriers.forEach(function(node) {
    if (!node.querySelector('.ck-discovery-bar')) return;
    if (node.querySelector('.ck-discovery-bar--failed') || node.querySelector('.ck-discovery-bar--completed')) return;
    anyDiscovering = true;
    var match = node.textContent.match(/(\d+)\s*\/\s*(\d+)/);
    if (match) {
      totalCurrent += parseInt(match[1], 10);
      totalTotal += parseInt(match[2], 10);
    }
  });
  if (anyDiscovering || ckRefreshing) {
    if (totalTotal > 0) {
      status.textContent = 'Refreshing models… ' + totalCurrent + '/' + totalTotal;
    } else {
      status.textContent = 'Refreshing models…';
    }
  }
}

document.addEventListener("turbo:before-stream-render", function(event) {
  var target = event.target.getAttribute("target");
  if (target && target.indexOf("discovery_status_") === 0) {
    requestAnimationFrame(ckUpdateRefreshProgress);
  }
  if (target === "prompt_llm_model" || target === "run_judge_model") {
    ckRefreshing = false;
    ckSetRefreshButtonsBusy(false);
    var status = document.getElementById('refresh-status');
    if (status) { status.textContent = 'Models updated.'; setTimeout(function() { status.textContent = ' '; }, 3000); }
  }
});

document.addEventListener("click", function(e) {
  document.querySelectorAll("details.ck-nav-menu[open], details.ck-settings-menu[open], details.ck-flyout[open]").forEach(function(menu) {
    if (!menu.contains(e.target)) menu.removeAttribute("open");
  });
});

function ckCheckEditor(scope) {
  if (!scope) return null;
  if (scope.matches && scope.matches("[data-ck-check-form]")) return scope;
  return scope.querySelector ? scope.querySelector("[data-ck-check-form]") : null;
}

function ckCheckForm(editor) {
  try {
    return JSON.parse(editor.getAttribute("data-ck-check-form"));
  } catch (e) {
    return null;
  }
}

function ckApplyCheckLabels(editor, form, kind) {
  var labels = form.labels[kind] || {};
  var hints = form.hints[kind] || {};
  editor.querySelectorAll("[data-ck-check-label]").forEach(function(node) {
    var key = node.getAttribute("data-ck-check-label");
    node.textContent = labels[key] || form.defaultLabels[key] || "";
  });
  editor.querySelectorAll("[data-ck-check-hint]").forEach(function(node) {
    var key = node.getAttribute("data-ck-check-hint");
    node.textContent = hints[key] || form.defaultHints[key] || "";
  });
}

function ckApplyCheckFields(scope) {
  var editor = ckCheckEditor(scope);
  if (!editor) return;
  var form = ckCheckForm(editor);
  if (!form) return;
  var kindSelect = editor.querySelector('[name="metric[check_config][check_kind]"]');
  if (!kindSelect) return;
  var kind = kindSelect.value;
  var visible = (form.fields[kind] || []).slice();
  var targetSelect = editor.querySelector('[name="metric[check_config][target]"]');
  var targetIsJsonPath = !!(targetSelect && targetSelect.value === "json_path");
  var expectedKey = form.expected[kind];

  if (expectedKey) {
    visible.push("compare_to");
    var comparison = editor.querySelector('[name="metric[check_config][compare_to]"]:checked');
    if (comparison && comparison.value === "expected") {
      visible = visible.filter(function(key) { return key !== expectedKey; });
      visible.push("expected_path");
    }
  }

  editor.querySelectorAll("[data-ck-check-field]").forEach(function(field) {
    var key = field.getAttribute("data-ck-check-field");
    var show;
    if (key === "target_path") {
      show = targetIsJsonPath;
    } else {
      show = visible.indexOf(key) !== -1;
    }
    field.hidden = !show;
  });

  ckApplyCheckLabels(editor, form, kind);
}

function ckApplyMetricType(group) {
  var checked = group.querySelector('input[type="radio"]:checked');
  if (!checked) return;
  var value = checked.value;
  var scope = group.closest("form") || document;
  scope.querySelectorAll("[data-ck-metric-editor]").forEach(function(editor) {
    var active = editor.getAttribute("data-ck-metric-editor") === value;
    editor.hidden = !active;
    editor.querySelectorAll("input, select, textarea").forEach(function(field) {
      field.disabled = !active;
    });
  });
  ckApplyCheckFields(scope);
}

function ckApplyMetricForms() {
  document.querySelectorAll("[data-ck-metric-type]").forEach(function(group) {
    ckApplyMetricType(group);
  });
  document.querySelectorAll("[data-ck-check-form]").forEach(function(editor) {
    ckApplyCheckFields(editor);
  });
}

document.addEventListener("turbo:load", ckApplyMetricForms);
document.addEventListener("turbo:render", ckApplyMetricForms);

document.addEventListener("change", function(e) {
  var target = e.target;
  if (!target || !target.closest) return;
  var group = target.closest("[data-ck-metric-type]");
  if (group && target.type === "radio") {
    ckApplyMetricType(group);
    return;
  }
  if (target.name === "metric[check_config][check_kind]" || target.name === "metric[check_config][target]" || target.name === "metric[check_config][compare_to]") {
    var scope = target.closest('[data-ck-metric-editor="check"]') || target.closest("form");
    ckApplyCheckFields(scope);
  }
});

function ckApplyProviderFields(scope) {
  if (!scope) return;
  var select = scope.querySelector("[data-ck-provider-select]");
  if (!select) return;
  var provider = select.value;
  scope.querySelectorAll("[data-ck-provider-field]").forEach(function(field) {
    var wanted = (field.getAttribute("data-ck-provider-field") || "").split(",");
    field.hidden = wanted.indexOf(provider) === -1;
  });
}

function ckApplyProviderForms() {
  document.querySelectorAll("[data-ck-provider-select]").forEach(function(select) {
    ckApplyProviderFields(select.closest("form") || document);
  });
}

document.addEventListener("turbo:load", ckApplyProviderForms);
document.addEventListener("turbo:render", ckApplyProviderForms);

document.addEventListener("change", function(e) {
  var target = e.target;
  if (target && target.matches && target.matches("[data-ck-provider-select]")) {
    ckApplyProviderFields(target.closest("form") || document);
  }
});

document.addEventListener("click", function(e) {
  var btn = e.target.closest("[data-ck-apply]");
  if (!btn) return;
  e.preventDefault();
  var targetName = btn.getAttribute("data-target");
  var value = btn.getAttribute("data-value");
  if (!targetName) return;
  var field = document.querySelector('[name="' + targetName.replace(/"/g, '\\"') + '"]');
  if (!field) return;
  field.value = value;
  field.dispatchEvent(new Event("input", { bubbles: true }));
  field.dispatchEvent(new Event("change", { bubbles: true }));
  btn.classList.add("is-applied");
  btn.textContent = "Applied ✓";
  field.focus({ preventScroll: true });
});

function ckSelectClose(sel) {
  if (!sel.classList.contains("is-open")) return;
  sel.classList.remove("is-open");
  var menu = sel.querySelector("[data-ck-select-menu]");
  var trigger = sel.querySelector("[data-ck-select-trigger]");
  if (menu) menu.hidden = true;
  if (trigger) trigger.setAttribute("aria-expanded", "false");
}

function ckSelectOpen(sel) {
  document.querySelectorAll("[data-ck-select].is-open").forEach(ckSelectClose);
  sel.classList.add("is-open");
  var menu = sel.querySelector("[data-ck-select-menu]");
  var trigger = sel.querySelector("[data-ck-select-trigger]");
  if (menu) menu.hidden = false;
  if (trigger) trigger.setAttribute("aria-expanded", "true");
  var current = menu.querySelector('[aria-selected="true"]') || menu.querySelector('[role="option"]');
  if (current) current.focus();
}

function ckSelectChoose(sel, option) {
  var input = sel.querySelector("[data-ck-select-value]");
  var label = sel.querySelector("[data-ck-select-label]");
  var text = option.querySelector("[data-ck-select-text]");
  sel.querySelectorAll('[role="option"]').forEach(function(o) {
    o.setAttribute("aria-selected", o === option ? "true" : "false");
  });
  input.value = option.getAttribute("data-value");
  if (text) label.textContent = text.textContent;
  input.dispatchEvent(new Event("change", { bubbles: true }));
  ckSelectClose(sel);
  var trigger = sel.querySelector("[data-ck-select-trigger]");
  if (trigger) trigger.focus();
}

document.addEventListener("click", function(e) {
  var trigger = e.target.closest("[data-ck-select-trigger]");
  if (trigger) {
    var sel = trigger.closest("[data-ck-select]");
    if (sel.classList.contains("is-open")) { ckSelectClose(sel); } else { ckSelectOpen(sel); }
    return;
  }
  var option = e.target.closest('[data-ck-select] [role="option"]');
  if (option) {
    ckSelectChoose(option.closest("[data-ck-select]"), option);
    return;
  }
  document.querySelectorAll("[data-ck-select].is-open").forEach(function(sel) {
    if (!sel.contains(e.target)) ckSelectClose(sel);
  });
});

document.addEventListener("keydown", function(e) {
  var sel = e.target.closest("[data-ck-select]");
  if (!sel) return;
  var trigger = sel.querySelector("[data-ck-select-trigger]");
  var options = Array.prototype.slice.call(sel.querySelectorAll('[role="option"]'));
  var open = sel.classList.contains("is-open");
  if (e.target === trigger && !open) {
    if (e.key === "ArrowDown" || e.key === "Enter" || e.key === " ") { e.preventDefault(); ckSelectOpen(sel); }
    return;
  }
  if (!open) return;
  var idx = options.indexOf(document.activeElement);
  if (e.key === "ArrowDown") { e.preventDefault(); (options[idx + 1] || options[0]).focus(); }
  else if (e.key === "ArrowUp") { e.preventDefault(); (options[idx - 1] || options[options.length - 1]).focus(); }
  else if (e.key === "Home") { e.preventDefault(); options[0].focus(); }
  else if (e.key === "End") { e.preventDefault(); options[options.length - 1].focus(); }
  else if (e.key === "Enter" || e.key === " ") { e.preventDefault(); if (options[idx]) ckSelectChoose(sel, options[idx]); }
  else if (e.key === "Escape") { e.preventDefault(); ckSelectClose(sel); trigger.focus(); }
});

function ckConfirmModal(message, formEl, submitter) {
  var dialog = document.getElementById("ck-confirm-modal");
  if (!dialog || typeof dialog.showModal !== "function") {
    return Promise.resolve(window.confirm(message));
  }
  var messageEl = dialog.querySelector("#ck-confirm-message");
  var acceptBtn = dialog.querySelector("[data-ck-confirm-accept]");
  var cancelBtn = dialog.querySelector("[data-ck-confirm-cancel]");
  if (messageEl) messageEl.textContent = message || "Are you sure?";
  var label = (submitter && submitter.getAttribute("data-ck-confirm-label")) || "Confirm";
  var tone = (submitter && submitter.getAttribute("data-ck-confirm-tone")) || "";
  if (acceptBtn) {
    acceptBtn.textContent = label;
    acceptBtn.className = "ck-button " + (tone === "danger" ? "ck-button--danger" : "ck-button--primary");
  }
  return new Promise(function(resolve) {
    function onClose() {
      dialog.removeEventListener("close", onClose);
      acceptBtn.removeEventListener("click", onAccept);
      cancelBtn.removeEventListener("click", onCancel);
      dialog.removeEventListener("click", onBackdrop);
      resolve(dialog.returnValue === "accept");
    }
    function onAccept() { dialog.close("accept"); }
    function onCancel() { dialog.close("cancel"); }
    function onBackdrop(e) { if (e.target === dialog) dialog.close("cancel"); }
    dialog.addEventListener("close", onClose);
    acceptBtn.addEventListener("click", onAccept);
    cancelBtn.addEventListener("click", onCancel);
    dialog.addEventListener("click", onBackdrop);
    dialog.returnValue = "";
    dialog.showModal();
    var focusTarget = (tone === "danger" ? cancelBtn : acceptBtn);
    if (focusTarget) focusTarget.focus();
  });
}

function ckInstallConfirm() {
  if (!window.Turbo) return;
  if (Turbo.config && Turbo.config.forms) {
    Turbo.config.forms.confirm = ckConfirmModal;
  } else if (typeof Turbo.setConfirmMethod === "function") {
    Turbo.setConfirmMethod(ckConfirmModal);
  }
}
document.addEventListener("turbo:load", ckInstallConfirm);
ckInstallConfirm();

var ckRowIgnoreSelector = "a, button, input, select, textarea, label, summary, form, dialog, [data-ck-row-ignore]";

function ckRowHref(e) {
  var target = e.target;
  if (!target || !target.closest) return null;
  var row = target.closest("[data-ck-href]");
  if (!row) return null;
  var inner = target.closest(ckRowIgnoreSelector);
  if (inner && row.contains(inner)) return null;
  return row.getAttribute("data-ck-href");
}

document.addEventListener("click", function(e) {
  var href = ckRowHref(e);
  if (!href) return;
  if (e.metaKey || e.ctrlKey || e.shiftKey) {
    window.open(href, "_blank");
  } else if (window.Turbo && typeof window.Turbo.visit === "function") {
    window.Turbo.visit(href);
  } else {
    window.location.assign(href);
  }
});

document.addEventListener("auxclick", function(e) {
  if (e.button !== 1) return;
  var href = ckRowHref(e);
  if (href) window.open(href, "_blank");
});

document.addEventListener("click", function(e) {
  if (e.target && e.target.closest && e.target.closest("[data-ck-stop-propagation]")) e.stopPropagation();
});

function ckShowDialog(dialog) {
  if (dialog && typeof dialog.showModal === "function" && !dialog.open) dialog.showModal();
}

document.addEventListener("click", function(e) {
  var target = e.target;
  if (!target || !target.closest) return;
  var opener = target.closest("[data-ck-dialog-open]");
  if (opener) {
    ckShowDialog(document.getElementById(opener.getAttribute("data-ck-dialog-open")));
    return;
  }
  var closer = target.closest("[data-ck-dialog-close]");
  if (closer) {
    var dialog = closer.closest("dialog");
    if (dialog) dialog.close();
    return;
  }
  if (target.matches("dialog[data-ck-dialog]")) target.close();
});

document.addEventListener("turbo:load", function() {
  ckShowDialog(document.querySelector("dialog[data-ck-dialog-autoopen]"));
});

function ckFlashCopied(el) {
  el.classList.add("ck-api-copy--done");
  setTimeout(function() { el.classList.remove("ck-api-copy--done"); }, 1500);
}

function ckCopyText(el, text) {
  navigator.clipboard.writeText(text).then(function() {
    if (el.hasAttribute("data-ck-copy-feedback")) ckFlashCopied(el);
  });
}

function ckToggleToken(el) {
  var showing = el.textContent === el.dataset.masked;
  el.textContent = showing ? el.dataset.real : el.dataset.masked;
  el.setAttribute("aria-pressed", showing ? "true" : "false");
  el.setAttribute("aria-label", showing ? "Hide API token" : "Reveal API token");
  navigator.clipboard.writeText(el.dataset.real).then(function() { ckFlashCopied(el); });
}

function ckCopyExample(btn) {
  var text = btn.closest(".ck-api-example").querySelector("pre").textContent;
  var realToken = btn.dataset.realToken;
  var displayToken = btn.dataset.displayToken;
  if (realToken && displayToken) text = text.split(displayToken).join(realToken);
  navigator.clipboard.writeText(text).then(function() { ckFlashCopied(btn); });
}

document.addEventListener("click", function(e) {
  var target = e.target;
  if (!target || !target.closest) return;
  var toggle = target.closest("[data-ck-token-toggle]");
  if (toggle) { ckToggleToken(toggle); return; }
  var example = target.closest("[data-ck-copy-example]");
  if (example) { ckCopyExample(example); return; }
  var literal = target.closest("[data-ck-copy-text]");
  if (literal) { ckCopyText(literal, literal.getAttribute("data-ck-copy-text")); return; }
  var copier = target.closest("[data-ck-copy]");
  if (!copier) return;
  var source = document.getElementById(copier.getAttribute("data-ck-copy"));
  if (source) ckCopyText(copier, source.textContent);
});

document.addEventListener("click", function(e) {
  var target = e.target;
  if (!target || !target.closest) return;
  if (target.closest("[data-ck-refresh-models]")) {
    ckRefreshModels();
    return;
  }
  var refresher = target.closest("[data-ck-provider-refresh]");
  if (!refresher) return;
  e.preventDefault();
  fetch(refresher.getAttribute("data-ck-provider-refresh"), {
    method: "POST",
    headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').getAttribute("content") }
  });
  ckStartDiscoveryPolling(8000);
});

document.addEventListener("click", function(e) {
  var toggle = e.target && e.target.closest && e.target.closest("[data-ck-prompt-toggle]");
  if (!toggle) return;
  var text = document.getElementById(toggle.getAttribute("aria-controls"));
  if (!text) return;
  var expanded = text.classList.toggle("ck-prompt-preview__text--expanded");
  toggle.firstChild.textContent = expanded ? "Show less" : "Show more";
  toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
});

function ckToggleMetricGroupFilter(btn) {
  btn.classList.toggle("tag-mark--off");
  var bar = btn.closest("[data-metric-tag-filter]");
  var grid = bar && bar.parentElement.querySelector("[data-metric-checkboxes]");
  if (!grid) return;
  var active = Array.prototype.map.call(
    bar.querySelectorAll(".ck-metric-tag-filter__chip:not(.tag-mark--off)"),
    function(b) { return b.getAttribute("data-filter-tag"); }
  );
  grid.querySelectorAll(".ck-checkbox-label").forEach(function(lbl) {
    var tags = (lbl.getAttribute("data-metric-tags") || "").split(",").filter(Boolean);
    var visible = active.length === 0 || tags.some(function(t) { return active.indexOf(t) !== -1; });
    lbl.style.display = visible ? "" : "none";
  });
}

document.addEventListener("click", function(e) {
  var target = e.target;
  if (!target || !target.closest) return;
  var chip = target.closest("[data-metric-tag-filter] [data-filter-tag]");
  if (chip) {
    ckToggleMetricGroupFilter(chip);
    return;
  }
  var group = target.closest("[data-metric-group]");
  if (group) ckToggleMetricGroup(group);
});

function ckUpdateRunForm() {
  var promptEl = document.getElementById('run_prompt_id');
  var judgeEl = document.getElementById('run_judge_model');
  var judgeOnlyEl = document.getElementById('run_judge_only');
  var judgeOnly = !!(judgeOnlyEl && judgeOnlyEl.checked);
  var promptField = document.getElementById('prompt-field');
  var outputColumnField = document.getElementById('output-column-field');
  var outputColumnEl = document.getElementById('run_output_column');
  if (promptField) promptField.hidden = judgeOnly;
  if (outputColumnField) outputColumnField.hidden = !judgeOnly;
  if (judgeOnly && promptEl) promptEl.value = '';

  var prompt = promptEl ? promptEl.value : '';
  var judge = judgeEl ? judgeEl.value : '';
  var judgeListed = !!judgeEl && judgeEl.type !== 'hidden';
  var metrics = document.querySelectorAll('input[name="run[metric_ids][]"]:checked');
  var judgeField = document.getElementById('judge-field');
  var metricsField = document.getElementById('metrics-field');
  var judgeHint = document.getElementById('judge-hint');
  var metricsHint = document.getElementById('metrics-hint');
  var submitBtn = document.getElementById('run-submit');

  if (judgeField) judgeField.className = 'ck-field';
  if (metricsField) metricsField.className = 'ck-field';
  if (judgeHint) judgeHint.textContent = '';
  if (metricsHint) metricsHint.textContent = '';

  var judgedMetrics = Array.prototype.filter.call(metrics, function(cb) {
    var lbl = cb.closest('[data-needs-judge]');
    return !!lbl && lbl.dataset.needsJudge === '1';
  });
  var judgeUnpaired = judgeListed && !!judge && metrics.length === 0;
  var metricsUnpaired = judgeListed && !judge && judgedMetrics.length > 0;
  if (judgeListed && judge && metrics.length > 0 && judgedMetrics.length === 0) {
    if (judgeHint) judgeHint.textContent = 'Checks need no judge, so this run will not use it.';
  } else if (judgeListed && judge && metrics.length > 0) {
    if (judgeHint) judgeHint.textContent = judgeOnly ? 'Existing outputs will be judged automatically.' : 'Responses will be generated then judged automatically.';
  } else if (judgeUnpaired) {
    if (judgeField) judgeField.className = 'ck-field ck-field--info';
    if (metricsField) metricsField.className = 'ck-field ck-field--info';
    if (metricsHint) metricsHint.textContent = 'Select at least one metric or group to enable judging.';
  } else if (metricsUnpaired) {
    if (judgeField) judgeField.className = 'ck-field ck-field--info';
    if (judgeHint) judgeHint.textContent = 'Select a judge model to enable judging.';
  }

  var datasetEl = document.getElementById('run_dataset_id');
  var datasetHint = document.getElementById('dataset-hint');
  var datasetField = document.getElementById('dataset-field');
  var dataset = datasetEl ? datasetEl.value : '';
  var selectedOption = promptEl ? promptEl.options[promptEl.selectedIndex] : null;
  var hasVars = selectedOption && selectedOption.dataset.hasVariables === '1';
  var promptVars = (selectedOption && selectedOption.dataset.variables ? selectedOption.dataset.variables.split(/,\s*/) : []).filter(Boolean);

  var missingVars = [];
  if (hasVars && dataset && datasetEl) {
    var datasetOption = datasetEl.options[datasetEl.selectedIndex];
    var headers = (datasetOption && datasetOption.dataset.headers ? datasetOption.dataset.headers.split(/,\s*/) : []).filter(Boolean);
    missingVars = promptVars.filter(function(v) { return headers.indexOf(v) === -1; });
  }

  if (datasetField) datasetField.className = 'ck-field';
  if (datasetHint) datasetHint.textContent = '';
  if (missingVars.length > 0) {
    if (datasetField) datasetField.className = 'ck-field ck-field--error';
    if (datasetHint) datasetHint.textContent = 'Dataset is missing ' + (missingVars.length === 1 ? 'column' : 'columns') + ' the prompt needs: ' + missingVars.join(', ');
  } else if (hasVars && !dataset) {
    if (datasetField) datasetField.className = 'ck-field ck-field--info';
    if (datasetHint) datasetHint.textContent = 'This prompt uses variables. Select a dataset to provide values.';
  }

  var expectedWarn = document.getElementById('expected-column-warn');
  var expectedField = document.getElementById('expected-column-field');
  var expectedColEl = document.getElementById('run_expected_column');
  if (expectedField) expectedField.className = 'ck-field';
  if (expectedWarn) expectedWarn.textContent = '';
  var wantsExpected = false;
  document.querySelectorAll('input[name="run[metric_ids][]"]:checked').forEach(function(cb) {
    var lbl = cb.closest('[data-compare-expected]');
    if (lbl && lbl.dataset.compareExpected === '1') wantsExpected = true;
  });
  if (wantsExpected && dataset && datasetEl) {
    var expOption = datasetEl.options[datasetEl.selectedIndex];
    var expHeaders = (expOption && expOption.dataset.headers ? expOption.dataset.headers.split(/,\s*/) : []).filter(Boolean);
    var expCol = ((expectedColEl && expectedColEl.value) || 'expected_output').trim();
    if (expHeaders.indexOf(expCol) === -1) {
      if (expectedField) expectedField.className = 'ck-field ck-field--error';
      if (expectedWarn) expectedWarn.textContent = "A selected check grades against each row's expected value, but this dataset has no \"" + expCol + "\" column, so every row would fail. Add the column or point this at the right one.";
    }
  }

  var summary = document.getElementById('prompt-summary');
  if (summary) {
    if (selectedOption && selectedOption.value) {
      var desc = selectedOption.dataset.description || '';
      var tmpl = selectedOption.dataset.templatePreview || '';
      var descEl = document.getElementById('prompt-summary-description');
      descEl.textContent = desc;
      descEl.hidden = !desc;
      document.getElementById('prompt-summary-template').textContent = tmpl;
      summary.hidden = false;
    } else {
      summary.hidden = true;
    }
  }

  var valid;
  if (judgeOnly) {
    valid = !!dataset;
    if (dataset && datasetEl && outputColumnEl) {
      var headersJudge = (datasetEl.options[datasetEl.selectedIndex] && datasetEl.options[datasetEl.selectedIndex].dataset.headers ? datasetEl.options[datasetEl.selectedIndex].dataset.headers.split(/,\s*/) : []).filter(Boolean);
      var col = (outputColumnEl.value || 'actual_output').trim();
      if (col === '' || headersJudge.indexOf(col) === -1) {
        valid = false;
        if (datasetField) datasetField.className = 'ck-field ck-field--error';
        if (datasetHint) datasetHint.textContent = "Dataset has no \"" + col + "\" column. Pick a different output column or dataset.";
      }
    } else if (!dataset) {
      if (datasetField) datasetField.className = 'ck-field ck-field--info';
      if (datasetHint) datasetHint.textContent = 'Skip generation and score responses you already have from a dataset column. Works with rubric metrics or deterministic checks.';
    }
  } else {
    valid = prompt !== '';
    if (hasVars && !dataset) valid = false;
    if (missingVars.length > 0) valid = false;
  }
  if (judgeUnpaired || metricsUnpaired) valid = false;
  if (submitBtn) submitBtn.disabled = !valid;

  ckUpdateMetricGroupsState();
}

function ckToggleMetricGroup(button) {
  var ids = (button.getAttribute('data-metric-ids') || '').split(',').filter(Boolean);
  var allChecked = ids.every(function(id) {
    var cb = document.getElementById('run_metric_' + id);
    return cb && cb.checked;
  });
  ids.forEach(function(id) {
    var cb = document.getElementById('run_metric_' + id);
    if (cb) cb.checked = !allChecked;
  });
  ckUpdateRunForm();
}

function ckUpdateMetricGroupsState() {
  document.querySelectorAll('[data-metric-group]').forEach(function(btn) {
    var ids = (btn.getAttribute('data-metric-ids') || '').split(',').filter(Boolean);
    if (ids.length === 0) return;
    var allChecked = ids.every(function(id) {
      var cb = document.getElementById('run_metric_' + id);
      return cb && cb.checked;
    });
    btn.classList.toggle('ck-metric-group-pill--active', allChecked);
  });
}

var ckRunFormChangeIds = ["run_judge_model", "run_prompt_id", "run_dataset_id", "run_judge_only"];

document.addEventListener("change", function(e) {
  var target = e.target;
  if (!target) return;
  if (ckRunFormChangeIds.indexOf(target.id) !== -1 || (target.type === "checkbox" && target.name === "run[metric_ids][]")) ckUpdateRunForm();
});

document.addEventListener("input", function(e) {
  if (e.target && e.target.id === "run_output_column") ckUpdateRunForm();
});

function ckInitRunForm() {
  if (document.getElementById("run_judge_only")) ckUpdateRunForm();
}

function ckDatasetHeaderPreview() {
  var area = document.getElementById("dataset_csv_data");
  var box = document.getElementById("dataset-header-preview");
  var chips = document.getElementById("dataset-header-chips");
  if (!area || !box || !chips) return;
  var recognized = { expected_output: "answer key", actual_output: "pre-made output" };
  var firstLine = (area.value.split(/\r?\n/).find(function(l) { return l.trim() !== ""; }) || "");
  var headers = firstLine.split(",").map(function(h) { return h.trim().replace(/^"|"$/g, ""); }).filter(Boolean);
  if (headers.length === 0) { box.hidden = true; chips.textContent = ""; return; }
  box.hidden = false;
  chips.textContent = "";
  headers.forEach(function(h) {
    var role = recognized[h];
    var chip = document.createElement("span");
    chip.className = "ck-header-chip" + (role ? " ck-header-chip--special" : "");
    chip.textContent = role ? h + " · " + role : h;
    chips.appendChild(chip);
  });
}

document.addEventListener("input", function(e) {
  if (e.target && e.target.id === "dataset_csv_data") ckDatasetHeaderPreview();
});

function ckInitPageForms() {
  ckInitRunForm();
  ckDatasetHeaderPreview();
}

document.addEventListener("turbo:load", ckInitPageForms);
document.addEventListener("turbo:render", ckInitPageForms);

function ckStartRunStatusPoll() {
  clearTimeout(window.ckRunStatusKick);
  clearInterval(window.ckRunStatusPoll);
  window.ckRunStatusKick = null;
  window.ckRunStatusPoll = null;
  var marker = document.querySelector("[data-ck-run-status-url]");
  if (!marker) return;
  var url = marker.getAttribute("data-ck-run-status-url");
  var refresh = function() {
    fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin" })
      .then(function(r) { return r.ok ? r.text() : null; })
      .then(function(html) { if (html) Turbo.renderStreamMessage(html); })
      .catch(function() {});
  };
  window.ckRunStatusKick = setTimeout(refresh, 1000);
  window.ckRunStatusPoll = setInterval(refresh, 15000);
}

document.addEventListener("turbo:load", ckStartRunStatusPoll);

ckInitPageForms();
