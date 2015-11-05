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
                            <span>Something went wrong. Please examine <b>/var/log/crowbar/install.log</b></span> \
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
                           <span>Installation was successful. You will be redirected in a few seconds.</span> \
                         </div> \
                         <div class='alert alert-info'> \
                           <span>If you want to install again please remove <b>/opt/dell/crowbar_framework/crowbar-installed-ok</b></span> \
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
