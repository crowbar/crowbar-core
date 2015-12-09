$(document).ready(function() {
  function statusCheck() {
    $.ajax({
      type: "GET",
      dataType: "json",
      url: Routes.status_installer_path(),
      success: function(data) {
        // check for invalid network.json
        $("#network-alert").remove();
        if (!data.validNetwork) {
          $(".button_to").find("input").prop("disabled", true);
          $(".panel")
            .parent()
            .parent()
            .prepend("<div id='network-alert' class='col-lg-12'>" +
                        "<div class='alert alert-danger'>" +
                          "<span>" + data.errorMsg + "</span>" +
                        "</div>" +
                      "</div>");
        } else {
          $(".button_to").find("input").prop("disabled", false);
        }
        // initially steps are empty, so we need to return
        if (!data.steps) {
          // indicate first step after triggering installation
          // otherwise the UI will take 3 seconds to catch up
          if (data.installing) {
            $("li.pre_sanity_checks").addClass("list-group-item-success");
            $("li.pre_sanity_checks span.fa")
              .removeClass("fa-hourglass-o")
              .addClass("fa-circle-o-notch fa-spin");
          }
          setTimeout(statusCheck, 3000);
          return;
        }
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
