$(document).ready(function() {
  function statusCheck() {
    $.ajax({
      type: "GET",
      dataType: "json",
      url: Routes.status_upgrade_path(),
      success: function(data) {
        if (data.installing) {
          current_step = data.steps[data.steps.length - 1];
          $("[step]").hide();
          $("[step="+current_step+"]").show();
          setTimeout(statusCheck, 3000);
        } else if (data.success) {
          $(":button").removeClass("disabled");
          $(".alert-success").show();
        } else if (data.failed) {
          $(".alert-danger").show();
        }
      },
      error: function() {
        setTimeout(statusCheck, 3000);
      }
    });
  }

  statusCheck();
});
