//= require_self

jQuery(document).ready(function($) {
  $('textarea.editor').each(function() {
    var cm = CodeMirror.fromTextArea(this, {
      lineNumbers: true,
      matchBrackets: true,
      tabSize: 2
    });

    $(this).data('codeMirror', cm);
  });

  $('[data-default]').each(function() {
    $(this).val(
      $(this).attr('data-default')
    );
  });

  $('[data-sslprefix]').each(function() {
    var afterInit = false;
    var prefix = $(this).data('sslprefix');

    var switcher = 'select[name={0}]'.format($(this).attr('id'));
    var container = '#{0}_container'.format(prefix);
    var target = '#{0}_generate_certs'.format(prefix);

    var key = $(this).data('sslkey');
    var cert = $(this).data('sslcert');

    $(switcher).live('change', function() {
      var val = $(this).val();

      if (val == true || val == 'true' || val == 'https') {
        $(container).show(100).removeAttr('checked');
      } else {
        $(container).hide(100).attr('disabled', 'disabled');
      }
    }).trigger('change');

    $(target).live('change', function() {
      var $parent = $(
        '#{0}_certfile, #{1}_keyfile, #{2}_insecure'.format(
          prefix,
          prefix,
          prefix
        )
      );

      if ($(this).val() == 'true') {
        $parent.attr('disabled', 'disabled');

        $('#{0}_certfile'.format(prefix)).val(cert).trigger('change');
        $('#{0}_keyfile'.format(prefix)).val(key).trigger('change');
        $('#{0}_insecure option'.format(prefix)).removeAttr('selected').siblings('[value=true]').attr('selected', true).trigger('change');
      } else {
        $parent.removeAttr('disabled');

        if (afterInit) {
          $('#{0}_insecure option'.format(prefix)).removeAttr('selected').siblings('[value=false]').attr('selected', true).trigger('change');
        }
      }
    }).trigger('change');

    afterInit = true;
  });

  $('[data-piechart]').sparkline('html', {
    type: 'pie',
    tagValuesAttribute: 'data-piechart',
    disableTooltips: true,
    disableHighlight: true,
    sliceColors: [
      '#0f0',
      '#f00',
      '#999',
      '#ff0'
    ]
  });

  $('[data-blockui]').live('submit', function(event) {
    $.blockUI({
      css: {
        border: 'none',
        padding: '15px',
        backgroundColor: '#000',
        '-webkit-border-radius': '10px',
        '-moz-border-radius': '10px',
        opacity: '.5',
        color: '#fff'
      },
      message: $(event.target).data('blockui')
    });
  });

  $('[data-blockui-click]').live('click', function(event) {
    $.blockUI({
      css: {
        border: 'none',
        padding: '15px',
        backgroundColor: '#000',
        '-webkit-border-radius': '10px',
        '-moz-border-radius': '10px',
        opacity: '.5',
        color: '#fff'
      },
      message: $(event.target).data('blockui-click')
    });
  });

  $('[data-checkall]').live('change', function(event) {
    var checker = $(event.target).data('checkall');

    if (event.target.checked) {
      $(checker).not(':disabled').attr('checked','checked');
    } else {
      $(checker).removeAttr('checked');
    }
  });

  $('[data-showit]').live('change keyup', function(event) {
    var $el = $(event.target);

    var targets = $el.data('showit-target').toString().split(';');
    var values = $el.data('showit').toString().split(';');

    $.each(targets, function(index, target) {
      var selects = values[index].toString().split(',');
      var $target = $(target);

      if (!$el.data('showit-direct')) {
        $target = $target.parent();
      }

      if ($target) {
        if ($.inArray($el.val(), selects) >= 0) {
          $target.show(100).removeAttr('disabled');
        } else {
          $target.hide(100).attr('disabled', 'disabled');
        }
      }
    });
  }).trigger('change');

  $('[data-hideit]').live('change keyup', function(event) {
    var $el = $(event.target);

    var targets = $el.data('hideit-target').toString().split(';');
    var values = $el.data('hideit').toString().split(';');

    $.each(targets, function(index, target) {
      var selects = values[index].toString().split(',');
      var $target = $(target);

      if (!$el.data('hideit-direct')) {
        $target = $target.parent();
      }

      if ($target) {
        if ($.inArray($el.val(), selects) >= 0) {
          $target.hide(100).attr('disabled', 'disabled');
        } else {
          $target.show(100).removeAttr('disabled');
        }
      }
    });
  }).trigger('change');

  $('[data-enabler]').live('change keyup', function(event) {
    var $el = $(event.target);

    var targets = $el.data('enabler-target').toString().split(';');
    var values = $el.data('enabler').toString().split(';');

    $.each(targets, function(index, target) {
      var selects = values[index].toString().split(',');
      var $target = $(target);

      if ($target) {
        if ($.inArray($el.val(), selects) >= 0) {
          $target.removeAttr('disabled');
        } else {
          $target.attr('disabled', 'disabled');
        }
      }
    });
  }).trigger('change');

  $('[data-disabler]').live('change keyup', function(event) {
    var $el = $(event.target);

    var targets = $el.data('disabler-target').toString().split(';');
    var values = $el.data('disabler').toString().split(';');

    $.each(targets, function(index, target) {
      var selects = values[index].toString().split(',');
      var $target = $(target);

      if ($target) {
        if ($.inArray($el.val(), selects) >= 0) {
          $target.attr('disabled', 'disabled');
        } else {
          $target.removeAttr('disabled');
        }
      }
    });
  }).trigger('change');

  $('[data-toggle-action]').live('click', function(e) {
    var target = '[data-toggle-target="{0}"]'.format(
      $(this).data('toggle-action')
    );

    e.preventDefault();

    if ($(target).hasClass('hidden')) {
      $(this).find('span').switchClass(
        "fa-chevron-right",
        "fa-chevron-down",
        0
      );

      $(target).switchClass(
        "hidden",
        "visible",
        0
      );
    } else {
      $(this).find('span').switchClass(
        "fa-chevron-down",
        "fa-chevron-right",
        0
      );

      $(target).switchClass(
        "visible",
        "hidden",
        0
      );
    }
  });

  $('[data-tooltip]').tooltip({
    html: true
  });

  $('[data-dynamic]').dynamicTable();
  $('[data-change]').updateAttribute();
  $('[data-listsearch]').listSearch();
  $('[data-ledupdate]').ledUpdate();
  $('[data-show-for-clusters-only="true"]').hideShowClusterConf();
  $('[data-hidetext]').hideShowText();

  $('#proposal_attributes, #proposal_deployment').changedState();
  $('#nodelist').nodeList();
  $('input[type=password]').hideShowPassword();

  setInterval(
    function() {
      $('.led.failed, .led.pending, .led.waiting, led.red').toggleClass('blink');
    },
    500
  );

  $('[data-toggle="tooltip"]').tooltip({html : true});
  $('[data-toggle="inline"]').popover({
    html : true,
    content: function() {
      return $($(this).data('inline')).html();
    }
  });

  $('body.backups input[name="api_v2_backup[file]"]').fileinput({
    uploadUrl: Routes.upload_api_v2_crowbar_backups_path({
      format: 'json'
    }),
    uploadAsync: true,
    allowedFileExtensions: ['tar.gz'],
    dropZoneEnabled: false
  })
  .on('fileuploaded', function() {
    location.reload();
  });

  $('body.installer-upgrades input[name="file"]').fileinput({
    showPreview: false,
    showUpload: false,
    uploadAsync: false,
    allowedFileExtensions: ['tar.gz'],
    dropZoneEnabled: false
  });
});

if (!String.prototype.localize) {
  String.prototype.localize = function() {
    var values = {
      'barclamp.node_selector.node_duplicate': 'Node {0} is already assigned to {1}',
      'barclamp.node_selector.cluster_duplicate': 'Cluster {0} is already assigned to {1}',
      'barclamp.node_selector.remotes_duplicate': 'Remote {0} is already assigned to {1}',
      'barclamp.node_selector.outdated': 'There have been deleted old nodes removed, please save this proposal.',
      'barclamp.node_selector.no_admin': 'Failed to assign {0} to {1}, no admin nodes allowed',
      'barclamp.node_selector.no_cluster': 'Failed to assign {0} to {1}, no clusters allowed',
      'barclamp.node_selector.no_remotes': 'Failed to assign {0} to {1}, no remotes allowed',
      'barclamp.node_selector.unique': 'Failed to assign {0} to {1}, it\'s already assigned to another role',
      'barclamp.node_selector.zero': 'Failed to assign {0} to {1}, no assignment allowed',
      'barclamp.node_selector.max_count': 'Failed to assign {0} to {1}, maximum of allowed nodes/clusters reached',
      'barclamp.node_selector.platform': 'Failed to assign {0} to {1}, this platform is not allowed',
      'barclamp.node_selector.exclude_platform': 'Failed to assign {0} to {1}, this platform is excluded',
      'barclamp.node_selector.conflicting_roles': 'Node {0} cannot be assigned to both {1} and any of these roles: {2}'
    };

    if (values[this]) {
      return values[this];
    } else {
      return this;
    }
  };
}
