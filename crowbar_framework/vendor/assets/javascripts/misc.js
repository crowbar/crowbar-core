//= require misc/format
//= require misc/arrayRemove
//= require misc/localizedValue
//= require misc/iefix
//= require misc/handlebars
//= require misc/mousetrap

$(document).ready(function($) {
  Handlebars.registerHelper('toString', function (x) {
    return (x === undefined) ? 'undefined' : x.toString();
  });
});
