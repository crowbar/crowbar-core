$(document).ready(function() {
  $("body.installer").each(function() {
    function statusCheck() {
      $.ajax({
        type: "GET",
        dataType: "json",
        url: Routes.installer_status_path(),
        success: function(data) {
          var mostRecent = $("li." + data.steps[data.steps.length-1]);
          var mostRecentIcon = mostRecent.children();

          $.each(data.steps, function (index, value) {
            $("li." + value)
              .removeClass("list-group-item-success")
              .children("span")
              .removeClass("fa-hourglass-o fa-circle-o-notch fa-spin")
              .addClass("fa-check");
          });
          mostRecentIcon.addClass("fa-check");

          if (data.failed) {
            mostRecent
              .next("li")
              .addClass("list-group-item-danger")
              .children("span")
              .removeClass("fa-hourglass-o fa-circle-o-notch fa-spin")
              .addClass("fa-times");
          } else {
            mostRecent
              .next("li")
              .addClass("list-group-item-success")
              .children("span")
              .removeClass("fa-hourglass-o")
              .addClass("fa-circle-o-notch fa-spin");
          }

          if (data.failed) {
            $(".panel")
              .parent()
              .parent()
              .prepend("<div class='col-lg-12'>" +
                          "<div class='alert alert-danger'>" +
                            "<span>" + data.errorMsg + "</span>" +
                          "</div>" +
                        "</div>");
          } else if (!data.success) {
            setTimeout(statusCheck, 3000);
          } else {
            $(".panel")
              .parent()
              .parent()
              .prepend("<div class='col-lg-12'>" +
                         "<div class='alert alert-success'>" +
                           "<span>" + data.successMsg + "</span>" +
                         "</div>" +
                         "<div class='alert alert-info'>" +
                           "<span>" + data.noticeMsg + "</span>" +
                         "</div>" +
                       "</div>");
            setTimeout(function(){
              window.location.replace(Routes.root_path());
            }, 10000);
          }
        },
        error: function() {
          setTimeout(statusCheck, 3000);
        }
      });
    }

    statusCheck();
  });
});
