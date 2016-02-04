$(document).ready(function() {
  if ($('body.installer-upgrades').length > 0) {
    $('[data-status-check]').each(function() {
      function statusCheck() {
        $.ajax({
          type: "GET",
          dataType: "json",
          url: Routes.status_upgrade_path(),
          success: function(data) {
            if (data.installing) {
              current_step = data.steps[data.steps.length - 1];

              $("[data-step]").addClass('hidden');
              $("[step=" + current_step + "]").removeClass('hidden');

              setTimeout(statusCheck, 3000);
            } else if (data.success) {
              $(":button").removeClass("disabled");
              $(".alert-success").removeClass('hidden');
            } else if (data.failed) {
              $(".alert-danger").removeClass('hidden');
            }
          },
          error: function() {
            setTimeout(statusCheck, 3000);
          }
        });
      }

      statusCheck();
    });

    $('[data-nodes-check]').each(function() {
      function nodesCheck() {
        $.ajax({
          type: "GET",
          dataType: "json",
          url: Routes.nodes_upgrade_path(),
          success: function(data) {
            $('[data-total]')
              .html(data.total);

            $('[data-left]')
              .html(data.left);

            $('[data-failed]')
              .html(data.failed);

            if (data.left > 0 || data.failed > 0) {
              setTimeout(nodesCheck, 3000);

              if (data.failed > 0) {
                $(".alert-danger")
                  .find('.message')
                    .html(data.error)
                  .end()
                  .removeClass('hidden');
              } else {
                $(".alert-danger").addClass('hidden');
              }
            } else {
              $(":button").removeClass("disabled");
              $(".alert-danger").addClass('hidden');
            }
          },
          error: function() {
            setTimeout(nodesCheck, 3000);
          }
        });
      }

      nodesCheck();
    });
  }
});
