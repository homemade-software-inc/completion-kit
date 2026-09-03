document.addEventListener("turbo:load", function() {
  document.querySelectorAll("[data-local-time]").forEach(function(el) {
    var d = new Date(el.getAttribute("datetime"));
    el.textContent = d.toLocaleString(undefined, {year:"numeric",month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"});
  });
  ckTickRelativeTimes();
  ckAutoFocusFirstError();
  if (ckDiscoveringInDom()) ckStartDiscoveryPolling(0);
});

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

var CK_CHECK_FIELDS = {
  contains: ["value", "case_sensitive", "trim"],
  not_contains: ["value", "case_sensitive", "trim"],
  equals: ["value", "case_sensitive", "trim"],
  regex: ["pattern", "case_sensitive", "multiline"],
  valid_json: [],
  json_path_equals: ["json_path", "expected"],
  length_bounds: ["min", "max"],
  set_overlap: ["value", "measure", "min", "case_sensitive"],
  numeric_bounds: ["min", "max"],
  numeric_equals: ["value", "tolerance", "tolerance_mode"]
};

var CK_EXPECTED_KEYS = {
  contains: "value",
  not_contains: "value",
  equals: "value",
  json_path_equals: "expected",
  set_overlap: "value",
  numeric_equals: "value"
};

var CK_CHECK_DEFAULT_LABELS = { min: "Minimum", max: "Maximum", value: "Text to look for" };

var CK_CHECK_LABELS = {
  length_bounds: { min: "Shortest allowed", max: "Longest allowed" },
  numeric_bounds: { min: "Lowest allowed", max: "Highest allowed" },
  set_overlap: { min: "Lowest score that passes", value: "Expected list" },
  numeric_equals: { value: "Expected number" }
};

var CK_CHECK_DEFAULT_HINTS = { min: "Leave blank for no lower bound." };

var CK_CHECK_HINTS = {
  set_overlap: { min: "Leave blank to require an exact match." }
};

function ckApplyCheckLabels(scope, kind) {
  var labels = CK_CHECK_LABELS[kind] || {};
  var hints = CK_CHECK_HINTS[kind] || {};
  scope.querySelectorAll("[data-ck-check-label]").forEach(function(node) {
    var key = node.getAttribute("data-ck-check-label");
    node.textContent = labels[key] || CK_CHECK_DEFAULT_LABELS[key];
  });
  scope.querySelectorAll("[data-ck-check-hint]").forEach(function(node) {
    var key = node.getAttribute("data-ck-check-hint");
    node.textContent = hints[key] || CK_CHECK_DEFAULT_HINTS[key];
  });
}

function ckApplyCheckFields(scope) {
  if (!scope) return;
  var kindSelect = scope.querySelector('[name="metric[check_config][check_kind]"]');
  if (!kindSelect) return;
  var kind = kindSelect.value;
  var visible = (CK_CHECK_FIELDS[kind] || []).slice();
  var targetSelect = scope.querySelector('[name="metric[check_config][target]"]');
  var targetIsJsonPath = !!(targetSelect && targetSelect.value === "json_path");
  var expectedKey = CK_EXPECTED_KEYS[kind];

  if (expectedKey) {
    visible.push("compare_to");
    var comparison = scope.querySelector('[name="metric[check_config][compare_to]"]:checked');
    if (comparison && comparison.value === "expected") {
      visible = visible.filter(function(key) { return key !== expectedKey; });
      visible.push("expected_path");
    }
  }

  scope.querySelectorAll("[data-ck-check-field]").forEach(function(field) {
    var key = field.getAttribute("data-ck-check-field");
    var show;
    if (key === "target_path") {
      show = targetIsJsonPath;
    } else {
      show = visible.indexOf(key) !== -1;
    }
    field.hidden = !show;
  });

  ckApplyCheckLabels(scope, kind);
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

document.addEventListener("turbo:load", function() {
  document.querySelectorAll("[data-ck-metric-type]").forEach(function(group) {
    ckApplyMetricType(group);
  });
  document.querySelectorAll('[data-ck-metric-editor="check"]').forEach(function(editor) {
    ckApplyCheckFields(editor);
  });
});

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

document.addEventListener("turbo:load", function() {
  document.querySelectorAll("[data-ck-provider-select]").forEach(function(select) {
    ckApplyProviderFields(select.closest("form") || document);
  });
});

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
