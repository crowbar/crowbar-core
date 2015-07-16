/**
 * Copyright 2011-2013, Dell
 * Copyright 2013-2014, SUSE LINUX Products GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

$(document).ready(function($) {
  $('#sql_engine').on('change', function() {
    var value = $(this).val();

    var types = [
      'mysql',
      'postgresql'
    ];

    var selector = $.map(types, function(val, index) {
      return '#{0}_container'.format(val);
    }).join(', ');

    var current = '#{0}_container'.format(
      value
    );

    $(selector).hide(100).attr('disabled', 'disabled');
    $(current).show(100).removeAttr('disabled');
  }).trigger('change');
});
