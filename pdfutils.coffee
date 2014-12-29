SCALE = 1.25
@draggingViewport = false
@currentPublication = null
@publicationHandle = null
@publicationCachedIdHandle = null
@myGroupsHandle = null

# We use our own reactive variable for publicationDOMReady and not Session to
# make sure it is not preserved when site autoreloads (because of a code change).
# Otherwise publicationDOMReady stored in Session would be restored to true which
# would be an invalid initial state. But on the other hand we want it to be
# a reactive value so that we can combine code logic easy.
@publicationDOMReady = new ReactiveVar false, (oldV, newV) ->
  console.log "ReactiveVar publicationDOMReady changed from " + oldV + " to " + newV
console.log "In PDFUtils.header: publicationDOMReady is " + publicationDOMReady.get()

# Mostly used just to force reevaluation of publicationHandle and publicationCachedIdHandle
@publicationSubscribing = new Variable false

# To be able to limit shown annotations only to those with highlights in the current viewport
@currentViewport = new Variable
  top: null
  bottom: null

# Variable containing currently realized (added to the DOM) highlights
@currentHighlights = new Variable {}

# Set this variable if you want the viewer to display a specific page when displaying next publication
@startViewerOnPage = null

@PDFUtils =

  show: (url, @_$displayWrapper) =>
    console.log "Showing publication"
    PDFUtils.showPDF(url)

  showPDF: (url) =>

    #@_$displayWrapper = document.getElementById('display-wrapper')

    @_pages = []
    @_pagesDone = 0
    publication = @

    @_highlighter = new Highlighter @_$displayWrapper, true

    PDFJS.getDocument(url).then (@_pdf) ->
      # Maybe this instance has been destroyed in meantime
      return if @_pages is null

      # To make sure we are starting with empty slate
      #@_$displayWrapper.empty()
      publicationDOMReady.set false
      currentViewport.set
        top: null
        bottom: null
      currentHighlights.set {}

      @_highlighter.setNumPages @_pdf.numPages

      for pageNumber in [1..@_pdf.numPages]
        #Blaze.renderWithData(Template['displayPage'], {pageNumber: pageNumber}, parentElement )
        $displayCanvas = $('<canvas/>').addClass('display-canvas').addClass('content-background').data('page-number', pageNumber)
        $highlightsCanvas = $('<canvas/>').addClass('highlights-canvas')
        $highlightsLayer = $('<div/>').addClass('highlights-layer')
        # We enable forwarding of mouse events from selection layer to highlights layer
        $selectionLayer = $('<div/>').addClass('text-layer').addClass('selection-layer').forwardMouseEvents()
        $highlightsControl = $('<div/>').addClass('highlights-control').append(
          $('<div/>').addClass('meta-menu').append(
            $('<i/>').addClass('icon-menu'),
            $('<div/>').addClass('meta-content'),
          )
        )
        $loading = $('<div/>').addClass('loading').text("Page #{ pageNumber }")

        $('<div/>').addClass(
          'display-page'
        ).addClass(
          'display-page-loading'
        ).attr(
          id: "display-page-#{ pageNumber }"
        ).append(
          $displayCanvas,
          $highlightsCanvas,
          $highlightsLayer,
          $selectionLayer,
          $highlightsControl,
          $loading,
        ).appendTo(@_$displayWrapper)

        do(pageNumber) =>
          console.log "In PDFUtils.showPDF: call @_pdf.getPage(pageNumber) for page " + pageNumber
          @_pdf.getPage(pageNumber).then (pdfPage) ->

            # Maybe this instance has been destroyed in meantime
            return if @_pages is null

            assert.equal pageNumber, pdfPage.pageNumber

            viewport = PDFUtils._viewport
              pdfPage: pdfPage # Dummy page object

            displayPage = $("#display-page-#{ pdfPage.pageNumber }", @_$displayWrapper).removeClass('display-page-loading')
            canvas = displayPage.find('canvas') # Both display and highlights canvases
            displayPage.css
              height: viewport.height
              width:  viewport.width
            canvas.attr
              height: viewport.height
              width:  viewport.width

            @_pages[pageNumber - 1 ] =
              pageNumber: pageNumber
              pdfPage: pdfPage
              rendering: false
            @_pagesDone++

            # instantiates a Page object which mimics the TextLayerBuilder function from PDFJs
            # up to here, the @_pages Array contains few items, no we fill it with the Page object
            console.log "In PDFUtils.showPDF: Call @_highlighter.setPage() for page " + pdfPage.pageNumber
            @_highlighter.setPage viewport, pdfPage

            # we write the pdf page content into the text-layer-dummy div
            console.log "In PDFUtils.showPDF: Call PDFUtils._getTextcontent() for page " + pdfPage.pageNumber
            PDFUtils._getTextContent pdfPage

            #@_progressCallback()

            # Check if new page should be maybe rendered?
            console.log "In PDFUtils.showPDF: Call PDFUtils.checkRender() for page " + pdfPage.pageNumber
            PDFUtils.checkRender()

            console.log "In PDFUtils.showPDF: Call setting publicationDOMReady to true for page " + pdfPage.pageNumber
            console.log @_pagesDone
            console.log @_pdf.numPages
            publicationDOMReady.set true if @_pagesDone is @_pdf.numPages
            console.log "In PDFUtils.showPDF: publicationDOMReady is set to " + publicationDOMReady.get() + " for page " + pdfPage.pageNumber

          , (args...) =>
            # TODO: Handle errors better (call destroy?, don't pass args as an array)
            console.log "Error getting page " + pageNumber

      $(window).on 'scroll.publication resize.publication', PDFUtils.checkRender

  _getTextContent: (pdfPage) =>
    console.log "In PDFUtils._getTextContent: Getting text content for page " + pdfPage.pageNumber

    pdfPage.getTextContent().then (textContent) =>
      # Maybe this instance has been destroyed in meantime
      return if @_pages is null
      console.log "In PDFUtils._getTextcontent: after getting the textContent, @_pages is"
      console.log @_pages

      @_highlighter.setTextContent pdfPage.pageNumber, textContent  # works

      fontSize = 21

      $displayPage = $("#display-page-#{ pdfPage.pageNumber }", @_$displayWrapper)
      $textLayerDummy = $('<div/>').addClass('text-layer-dummy').css('font-size', fontSize).text(@_highlighter.extractText pdfPage.pageNumber)
      console.log "In @PDFUtils._getTextContent: $textLayerDummy for page " + pdfPage.pageNumber + " is "
      console.log $textLayerDummy
      $displayPage.append($textLayerDummy)
      console.log "In @PDFUtils._getTextContent: $displayPage for page " + pdfPage.pageNumber + " is "
      console.log $displayPage

      while $textLayerDummy.outerHeight(true) > $displayPage.height() and fontSize > 1
        fontSize--
        $textLayerDummy.css('font-size', fontSize)

      console.log "In @PDFUtils._getTextContent: Getting text content for page " + pdfPage.pageNumber + " complete"

      # Check if the page should be maybe rendered, but we
      # skipped it because text content was not yet available
      console.log "In PDFUtils._getTextContent: call checkRender() for page " + pdfPage.pageNumber
      PDFUtils.checkRender()

    , (args...) =>
      # TODO: Handle errors better (call destroy?, don't pass args as an array)
      console.log "Error getting text content for page " + pdfPage.pageNumber

  checkRender: =>
    for page in @_pages or []
      console.log "In PDFUtils.checkRender: page.rendering for page " + page.pdfPage.pageNumber + " is "
      console.log page.rendering

      continue if page.rendering

      # When rendering we also set text segment locations for what we need text
      # content to be already available, so if we are before text content has
      # been set, we skip (it will be retried after text content is set)
      continue unless @_highlighter.hasTextContent page.pageNumber

      $canvas = $("#display-page-#{ page.pageNumber } canvas", @_$displayWrapper)
      console.log "In PDFUtils.checkRender: $canvas for page " + page.pageNumber + " is"
      console.log $canvas

      canvasTop = $canvas.offset().top
      canvasBottom = canvasTop + $canvas.height()
      console.log "In PDFUtils.checkRender: canvasTop = " + canvasTop + ", canvasBottom = " + canvasBottom + " for page " + page.pageNumber
      console.log "In PDFUtils.checkRender: $(window).scrollTop() = " + $(window).scrollTop() + ", $(window).height() = " + $(window).height() + " for page " + page.pageNumber
      console.log "In PDFUtils.checkRender: Start if " + (canvasTop - 100) + " <= " + ($(window).scrollTop() + $(window).height()) + " and " + (canvasBottom + 100) + " >= " + $(window).scrollTop()
      #Add 100px so that we start rendering early
      if canvasTop - 100 <= $(window).scrollTop() + $(window).height() and canvasBottom + 100 >= $(window).scrollTop()
        console.log "In PDFUtils.checkRender: Call renderPage for page " + page.pageNumber
        PDFUtils.renderPage page

    return # Make sure CoffeeScript does not return anything

  renderPage: (page) =>
    console.log "In PDFUtils.renderPage: start function call for page " + page.pdfPage.pageNumber
    console.log "In PDFUtils.renderPage: page.rendering for page " + page.pdfPage.pageNumber + " is "
    console.log page.rendering

    # stops here if page already rendering -> if not, turns rendering true
    return if page.rendering
    page.rendering = true
    console.log "In PDFUtils.renderPage: Turned page.rendering for page " + page.pdfPage.pageNumber
    console.log page.rendering

    $displayPage = $("#display-page-#{ page.pageNumber }", @_$displayWrapper)
    $canvas = $displayPage.find('canvas')

    # Redo canvas resize to make sure it is the right size
    # It seems sometimes already resized canvases are being deleted and replaced with initial versions
    viewport = PDFUtils._viewport page
    $canvas.attr
      height: viewport.height
      width: viewport.width
    $displayPage.css
      height: viewport.height
      width: viewport.width

    console.log "In PDFUtils.renderPage: Generating PDFUtils.renderPage.renderContent for page " + page.pdfPage.pageNumber
    console.log page
    renderContext =
      canvasContext: $canvas.get(0).getContext '2d'
      imageLayer: @_highlighter.imageLayer page.pageNumber
      viewport: PDFUtils._viewport page
    console.log "In PDFUtils.renderPage: renderContext for page " + page.pdfPage.pageNumber + " is"
    console.log renderContext

    console.log "In PDFUtils.renderPage: Calling page.pdfPage.render(renderContext) for page " + page.pdfPage.pageNumber
    console.log "In PDFUtils.renderPage: test for @_pages"
    console.log @_pages
    page.pdfPage.render(renderContext).promise.then =>
      # Maybe this instance has been destroyed in meantime
      return if @_pages is null

      console.log "!!! In PDFUtils.renderPage: Rendering page " + page.pdfPage.pageNumber + " complete"
      console.log "In PDFUtils.renderPage: hide .loading for page " + page.pageNumber
      $("#display-page-#{ page.pageNumber } .loading", @_$displayWrapper).hide()

      # Maybe we have to render text layer as well
      console.log "In PDFUtils.renderPage: Calling @_highlighter.checkRender() for page " + page.pdfPage.pageNumber
      @_highlighter.checkRender()

    , (args...) =>
      # TODO: Handle errors better (call destroy?, don't pass args as an array)
      console.log "Error rendering page " + page.pdfPage.pageNumber

  _viewport: (page) =>
    scale = SCALE
    page.pdfPage.getViewport scale
    ###
    desiredWidth =  $('#display-wrapper').width()
    _viewport = page.pdfPage.getViewport(1)
    scale = desiredWidth / _viewport.width
    page.pdfPage.getViewport scale
    ###
