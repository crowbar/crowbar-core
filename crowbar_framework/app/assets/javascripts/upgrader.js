$(document).ready(function() {
  function statusCheck() {
    $.ajax({
      type: "GET",
      dataType: "json",
      url: Routes.restore_status_backups_path(),
      success: function(data) {
        if (data.restoring) {
          current_step = data.steps[data.steps.length - 1];
          $("[step]").hide();
          $("[step="+current_step+"]").show();
          setTimeout(statusCheck, 3000);
        } else if (data.success) {
          $(":button").removeClass("disabled");
          $(".restore_button").addClass("disabled");
          $(".alert-info").hide();
          $(".alert-success").show();
        } else if (data.failed) {
          $(".alert-info").hide();
          $(".alert-danger").show();
          $(".restore_button").addClass("disabled");
        }
      },
      error: function() {
        setTimeout(statusCheck, 3000);
      }
    });
  }

  statusCheck();
});
