$(document).ready(function() {
  $("body.installer").each(function() {
    function statusCheck() {
      $.ajax({
        type: "GET",
        dataType: "json",
        url: Routes.installer_status_path(),
        success: function(data) {
          var failed = data.failed;
          var success = data.success;
          var errorMsg = data.errorMsg
          var successMsg = data.successMsg
          var noticeMsg = data.noticeMsg
          data = data.steps;
          var mostRecent = $("li." + data[data.length-1]);
          var mostRecentIcon = mostRecent.children();

          $.each(data, function (index, value) {
            $("li." + value)
              .removeClass("list-group-item-success")
              .children("span")
              .removeClass("fa-hourglass-o fa-circle-o-notch fa-spin")
              .addClass("fa-check");
          });

          mostRecentIcon.removeClass(function (index, css) {
            var match = css.match(/^fa-/g);
            if (match !== null) {
              return match.join("");
            }
          });
          mostRecentIcon.addClass("fa-check");

          if (failed) {
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

          if (failed) {
            $(".panel")
              .parent()
              .parent()
              .prepend("<div class='col-lg-12'> \
                          <div class='alert alert-danger'> \
                            <span>" + errorMsg + "</span> \
                          </div> \
                        </div>");
          } else if (!success) {
            setTimeout(statusCheck, 3000);
          } else {
            $(".panel")
              .parent()
              .parent()
              .prepend("<div class='col-lg-12'> \
                         <div class='alert alert-success'> \
                           <span>" + successMsg + "</span> \
                         </div> \
                         <div class='alert alert-info'> \
                           <span>" + noticeMsg + "</span> \
                         </div> \
                       </div>");
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
