var handleKeyBindings;

$(function() {
  return handleKeyBindings();
});

$(document).on('page:change', function() {
  return handleKeyBindings();
});

handleKeyBindings = function() {
  Mousetrap.reset();
  $('a[data-keybinding]').each(function(i, el) {
    var bindedKey;
    bindedKey = $(el).data('keybinding');
    if (typeof bindedKey === 'number') {
      bindedKey = bindedKey.toString();
    }
    return Mousetrap.bind(bindedKey, function(e) {
      if (typeof Turbolinks === 'undefined') {
        return el.click();
      } else {
        return Turbolinks.visit(el.href);
      }
    });
  });
  $('input[data-keybinding]').each(function(i, el) {
    return Mousetrap.bind($(el).data('keybinding'), function(e) {
      el.focus();
      if (e.preventDefault) {
        return e.preventDefault();
      } else {
        return e.returnValue = false;
      }
    });
  });

  // keybindings
  Mousetrap.bind('h', function() {
    $("#keybindings_modal").modal("show");
  });

  Mousetrap.bind('d', function() {
    window.location = Routes.dashboard_path();
  });

  Mousetrap.bind('b e', function() {
    window.location = Routes.nodes_list_path();
  });

  Mousetrap.bind('a r', function() {
    window.location = Routes.active_roles_path();
  });

  Mousetrap.bind('f g', function() {
    window.location = Routes.nodes_families_path();
  });

  Mousetrap.bind('n s', function() {
    window.location = Routes.network_path();
  });

  Mousetrap.bind('v', function() {
    window.location = Routes.vlan_path("default");
  });

  Mousetrap.bind('a b', function() {
    window.location = Routes.barclamp_modules_path();
  });

  Mousetrap.bind('c b', function() {
    window.location = Routes.index_barclamp_path("crowbar");
  });

  Mousetrap.bind('o b', function() {
    window.location = Routes.index_barclamp_path("openstack");
  });

  Mousetrap.bind('q', function() {
    window.location = Routes.deployment_queue_path();
  });

  Mousetrap.bind('r', function() {
    window.location = Routes.repositories_path();
  });

  Mousetrap.bind('b r', function() {
    window.location = Routes.backups_path();
  });

  Mousetrap.bind('e', function() {
    window.location = Routes.utils_path();
  });

  Mousetrap.bind('s d', function() {
    window.location = Routes.swift_dashboard_path();
  });

  Mousetrap.bind('c u', function() {
    window.location = Routes.ucs_settings_path();
  });

  if (mouseTrapRails.showOnLoad) {
    return mouseTrapRails.toggleHints();
  }
};
