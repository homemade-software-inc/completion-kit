document.addEventListener("turbo:load", function() {
  document.querySelectorAll("[data-local-time]").forEach(function(el) {
    var d = new Date(el.getAttribute("datetime"));
    el.textContent = d.toLocaleString(undefined, {year:"numeric",month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"});
  });
  ckTickRelativeTimes();
  ckAutoFocusFirstError();
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
document.addEventListener("mouseover", function(e) {
  var row = e.target.closest && e.target.closest(".ck-csv-table tbody tr");
  if (!row || row === ckCsvHoverRow) return;
  if (ckCsvHoverRow) ckCsvHoverRow.classList.remove("ck-csv-row--expanded");
  ckCsvHoverRow = row;
  clearTimeout(ckCsvHoverTimer);
  ckCsvHoverTimer = setTimeout(function() {
    if (ckCsvHoverRow === row) row.classList.add("ck-csv-row--expanded");
  }, 350);
});
document.addEventListener("mouseout", function(e) {
  var row = e.target.closest && e.target.closest(".ck-csv-table tbody tr");
  if (!row) return;
  var related = e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest(".ck-csv-table tbody tr");
  if (related === row) return;
  clearTimeout(ckCsvHoverTimer);
  row.classList.remove("ck-csv-row--expanded");
  if (ckCsvHoverRow === row) ckCsvHoverRow = null;
});

var ckRefreshing = false;
function ckSetRefreshButtonsBusy(busy) {
  document.querySelectorAll('.ck-icon-btn[title="Refresh models"]').forEach(function(btn) {
    btn.classList.toggle('ck-icon-btn--spinning', busy);
    btn.disabled = busy;
  });
}
function ckRefreshModels() {
  if (ckRefreshing) return;
  ckRefreshing = true;
  ckSetRefreshButtonsBusy(true);
  ckUpdateRefreshProgress();
  var csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute("content");
  fetch("/completion_kit/refresh_models", {
    method: "POST",
    headers: { "X-CSRF-Token": csrfToken }
  });
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
