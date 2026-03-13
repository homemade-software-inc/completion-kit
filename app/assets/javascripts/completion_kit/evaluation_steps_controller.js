document.addEventListener("DOMContentLoaded", function () {
  document.addEventListener("click", function (event) {
    var addBtn = event.target.closest("[data-action='evaluation-steps#add']");
    if (addBtn) {
      var container = addBtn.closest("[data-controller='evaluation-steps']");
      var list = container.querySelector("[data-evaluation-steps-target='list']");
      var row = document.createElement("div");
      row.className = "ck-step-row";
      row.setAttribute("data-evaluation-steps-target", "row");
      row.innerHTML =
        '<input type="text" name="metric[evaluation_steps][]" value="" class="ck-input" placeholder="Describe this evaluation step..." />' +
        '<button type="button" class="ck-icon-btn" data-action="evaluation-steps#remove" aria-label="Remove step">' +
        '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.75"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>' +
        "</button>";
      list.appendChild(row);
      row.querySelector("input").focus();
    }

    var removeBtn = event.target.closest("[data-action='evaluation-steps#remove']");
    if (removeBtn) {
      var stepRow = removeBtn.closest("[data-evaluation-steps-target='row']");
      if (stepRow) stepRow.remove();
    }
  });
});
