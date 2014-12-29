Package.describe({
  name: 'jhartma:pdfutils',
  summary: 'Easily display PDFs',
  version: '0.0.1',
  git: ' /* Fill me in! */ '
});

Package.onUse(function(api) {
  api.versionsFrom('1.0.2.1')
  api.use(['deps',
           'underscore',
           'templating',
           'handlebars',
           'coffeescript',
           'stylus',
           'jquery',
           'peerlibrary:pdf.js@1.0.791_4'
  ], 'client')
  api.use([
    'deps',
    'underscore',
    'coffeescript'
  ], 'server');
  api.use([
    'reactive-var',
    'awwx:variable',
    'peerlibrary:assert'
    ], ['client','server'])

  api.addFiles('client/stylesheets/variables.import.styl', 'client');
  api.addFiles('client/stylesheets/displayPDF.styl', 'client');
  api.addFiles('client/compatibility/jQuery.forwardMouseEvents.js','client');
  api.addFiles('client/compatibility/jQuery.balanceText.js','client');
  api.addFiles('client/compatibility/jQuery.dimensions.coffee','client');
  api.addFiles('client/compatibility/jQuery.ui-git.js','client');
  api.addFiles('lib/pdf.coffee');
  api.addFiles('lib/page.coffee');
  api.addFiles('lib/highlighter.coffee');
  api.addFiles('pdfutils.coffee', 'client');
  api.addFiles('global_variables.js', 'client');
  api.addFiles('client/displayPDF.html','client');
  api.addFiles('client/displayPDF.coffee', 'client');
  api.export('PDFUtils');

});

Package.onTest(function(api) {
  api.use('tinytest');
  api.use('jhartma:pdf');
  api.addFiles('pdfutils-tests.coffee');
});
