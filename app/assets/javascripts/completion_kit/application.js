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

// Verdict button handling
document.addEventListener("click", function(e) {
  var btn = e.target.closest(".ck-verdict-btn");
  if (!btn) return;
  
  var container = btn.closest(".ck-verdict-buttons");
  var detail = container.nextElementSibling;
  var verdict = btn.getAttribute("data-verdict");
  
  if (verdict === "disagree") {
    // Show the slider/note panel
    if (detail && detail.classList.contains("ck-verdict-detail")) {
      detail.style.display = detail.style.display === "none" ? "block" : "none";
    }
    return;
  }
  
  // For agree/borderline, submit immediately
  submitVerdict(container, verdict);
});

document.addEventListener("click", function(e) {
  var submitBtn = e.target.closest(".ck-verdict-submit");
  if (!submitBtn) return;
  
  var container = submitBtn.closest(".ck-verdict-buttons");
  var detail = container.nextElementSibling;
  var verdict = "disagree";
  
  submitVerdict(container, verdict, detail);
});

function submitVerdict(container, verdict, detail) {
  var runId = container.getAttribute("data-run-id");
  var responseId = container.getAttribute("data-response-id");
  var metricId = container.getAttribute("data-metric-id");
  var anonymousId = container.getAttribute("data-anonymous-id");

  // Ensure anonymous_id is persisted in a cookie
  if (!getCookie("verdict_anonymous_id")) {
    setCookie("verdict_anonymous_id", anonymousId, 365);
  }

  var payload = {
    calibration: {
      run_id: runId,
      response_id: responseId,
      metric_id: metricId || null,
      anonymous_id: anonymousId,
      verdict: verdict
    }
  };
  
  // If disagree and detail panel is present, include corrected_score and note
  if (verdict === "disagree" && detail) {
    var slider = detail.querySelector(".ck-slider");
    var textarea = detail.querySelector(".ck-textarea");
    if (slider) payload.calibration.corrected_score = parseFloat(slider.value);
    if (textarea && textarea.value.trim()) payload.calibration.note = textarea.value.trim();
  }
  
  var csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute("content");
  
  fetch("/completion_kit/calibrations", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": csrfToken,
      "Accept": "application/json"
    },
    body: JSON.stringify(payload)
  })
  .then(function(response) {
    if (response.ok) {
      // Update button states to show selected
      container.querySelectorAll(".ck-verdict-btn").forEach(function(b) {
        b.classList.remove("ck-verdict-btn--selected");
      });
      container.querySelector("[data-verdict='" + verdict + "']").classList.add("ck-verdict-btn--selected");
      
      // Hide detail panel after submit
      if (detail) detail.style.display = "none";
    }
  });
}

// Slider value display
document.addEventListener("input", function(e) {
  if (!e.target.classList.contains("ck-slider")) return;
  var valueDisplay = e.target.nextElementSibling;
  if (valueDisplay && valueDisplay.classList.contains("ck-slider-value")) {
    valueDisplay.textContent = e.target.value;
  }
});

// Cookie helpers for anonymous ID persistence
function getCookie(name) {
  var match = document.cookie.match(new RegExp('(?:^|\\s)' + name + '=([^;]*)'));
  return match ? match[1] : null;
}

function setCookie(name, value, days) {
  var expires = new Date();
  expires.setTime(expires.getTime() + days * 864e5);
  document.cookie = name + '=' + encodeURIComponent(value) + ';expires=' + expires.toUTCString() + ';path=/';
}

// Ensure anonymous_id cookie exists
(function() {
  if (!getCookie('verdict_anonymous_id')) {
    setCookie('verdict_anonymous_id', crypto.randomUUID(), 365);
  }
})();
