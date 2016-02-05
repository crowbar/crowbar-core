$(document).ready(function() {
  function flash(message) {
    $(".panel")
      .parent()
      .parent()
      .prepend(message);
  }

  function setInMotion(selector) {
    selector
      .addClass("list-group-item-success");
    selector.find("span.fa")
      .removeClass("fa-hourglass-o")
      .addClass("fa-circle-o-notch fa-spin");
  }

  function setFailed(selector) {
    selector
      .removeClass("list-group-item-success")
      .addClass("list-group-item-danger")
      .children("span")
      .removeClass("fa-hourglass-o fa-circle-o-notch fa-spin")
      .addClass("fa-times");
  }

  function setSuccess(selector) {
    selector
      .removeClass("list-group-item-success")
      .children("span")
      .removeClass("fa-hourglass-o fa-circle-o-notch fa-spin")
      .addClass("fa-check");
  }

  function statusCheck() {
    $.ajax({
      type: "GET",
      dataType: "json",
      url: Routes.status_installer_path(),
      success: function(data) {
        // check for invalid network.json
        $("#network-alert").remove();
        if (!data.network.valid) {
          $(".button_to").find("input").prop("disabled", true);
          flash("<div id='network-alert' class='col-lg-12'>" +
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
            setInMotion($("li.pre_sanity_checks"));
          }
          // if we fail early before the first step is done, we have to report
          // back to the UI https://bugzilla.suse.com/show_bug.cgi?id=958766
          if (data.failed) {
            setFailed($("li.pre_sanity_checks"));
            flash("<div id='network-alert' class='col-lg-12'>" +
                    "<div class='alert alert-danger'>" +
                      "<span>" + data.errorMsg + "</span>" +
                    "</div>" +
                  "</div>");
            return;
          }
          setTimeout(statusCheck, 3000);
          return;
        }
        var mostRecent = $("li." + data.steps[data.steps.length-1]);
        var mostRecentIcon = mostRecent.children();

        $.each(data.steps, function (index, value) {
          setSuccess($("li." + value));
        });
        mostRecentIcon.addClass("fa-check");

        if (data.failed) {
          setFailed(mostRecent.next("li"));
        } else {
          setInMotion(mostRecent.next("li"));
        }

        if (data.failed) {
          flash("<div class='col-lg-12'>" +
                  "<div class='alert alert-danger'>" +
                    "<span>" + data.errorMsg + "</span>" +
                  "</div>" +
                "</div>");
        } else if (!data.success) {
          setTimeout(statusCheck, 3000);
        } else {
            flash("<div class='col-lg-12'>" +
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
