/**
 * Copyright 2011-2013, Dell
 * Copyright 2013-2015, SUSE Linux GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Author: SUSE Linux GmbH
 */

;(function($) {
  function HideShowText(el, options) {
    this.$el = $(el);

    this.defaults = {
      secretTarget: 'hidetext-secret',
      classTarget: 'hidetext-class',
      firstToggle: true
    };

    this.options = $.extend(
      this.defaults,
      options
    );

    this.init();
  }

  HideShowText.prototype.init = function() {
    var self = this;
    var secret;
    var placeholder;

    if (self.$el.data(self.options.secretTarget) === undefined) {
      secret = self.$el.text();
      placeholder = self.createSecret(secret);
    } else {
      secret = self.$el.data(self.options.secretTarget);
      placeholder = self.createSecret(secret);
    }

    self.$el.data(
      self.options.secretTarget,
      secret
    );

    self.writeContent(
      placeholder
    );

    self.$el.on('click', 'div.toggle-text', function(e) {
      e.preventDefault();
      self.toggleText();
    });
  };

  HideShowText.prototype.toggleText = function() {
    var self = this;

    var inner = self.$el
      .find('.hidetext-text')
      .text();

    var outer = self.$el
      .data(self.options.secretTarget);

    self.$el
      .data(self.options.secretTarget, inner)
      .children('.hidetext-text')
        .html(outer)
      .end()
      .children('.toggle-text')
        .toggleClass('toggle-text-show toggle-text-hide');
  };

  HideShowText.prototype.createSecret = function(secret) {
    var self = this;
    var placeholder = '';

    for (var i = 0; i < secret.length; i++)  {
      placeholder += "&#149;";
    }

    return placeholder;
  };

  HideShowText.prototype.writeContent = function(secret) {
    var self = this;

    self.$el
      .text("")
      .append(
        [
          '<span class="hidetext-text">',
            '{0}',
          '</span>',
          '<div class="toggle-text toggle-text-show {1}">',
            '&nbsp;',
          '</div>'
        ].join(
          ''
        ).format(
          secret,
          self.$el.data(
            self.options.classTarget
          )
        )
      );
  };

  $.fn.hideShowText = function(options) {
    return this.each(function() {
      new HideShowText(this, options);
    });
  };
}) (jQuery);
