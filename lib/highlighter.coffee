class @Highlighter
  constructor: (@_$displayWrapper, isPdf) ->
    constructor: (@_$displayWrapper, isPdf) ->
    @_pages = []
    @_numPages = null
    @mouseDown = false

    @_highlightsHandle = null
    @_highlightLocationHandle = null

    #@_annotator = new Annotator @, @_$displayWrapper

    #@_annotator.addPlugin 'CanvasTextHighlights'
    #@_annotator.addPlugin 'DomTextMapper'
    #@_annotator.addPlugin 'TextAnchors'
    #@_annotator.addPlugin 'TextRange'
    #@_annotator.addPlugin 'TextPosition'
    #@_annotator.addPlugin 'TextQuote'
    #@_annotator.addPlugin 'DOMAnchors'

    #@_annotator.addPlugin 'PeerLibraryPDF' if isPdf

    # Annotator.TextPositionAnchor does not seem to be set globally from the
    # TextPosition's pluginInit, so let's do it here again
    # TODO: Can this be fixed somehow?
    #Annotator.TextPositionAnchor = @_annotator.plugins.TextPosition.Annotator.TextPositionAnchor

    $(window).on 'scroll.highlighter resize.highlighter', @checkRender if isPdf

  checkRender: =>
    pagesToRender = []
    pagesToRemove = []

    console.log "In @Highlighter.checkRender: start looping through pages"
    console.log @_pages

    for page in @_pages
      # If page is just in process of being rendered, we skip it
      console.log "In @Highlighter.checkRender: Starting @Highlighter.checkRender for page " + page.pageNumber
      continue if page.rendering
      console.log 'In @Highlighter.checkRender: Text layer for page ' + page.pageNumber + ' is rendering'

      # Page is not yet ready
      console.log "In @Highlighter.checkRender: Highlights for page " + page.pageNumber + " enabled " + page.highlightsEnabled
      continue unless page.highlightsEnabled
      console.log 'In @Highlighter.checkRender: Text layer for page ' + page.pageNumber + ' is ready'

      $canvas = page.$displayPage.find('canvas')
      console.log "In @Highlighter.checkRender: $canvas is"
      console.log $canvas

      canvasTop = $canvas.offset().top
      console.log "In @Highlighter.checkRender: canvasTop for page " + page.pageNumber + " is " + canvasTop
      canvasBottom = canvasTop + $canvas.height()
      console.log "In @Highlighter.checkRender: canvasBottom for page " + page.pageNumber + " is " + canvasBottom
      # Add 500px so that we start rendering early
      if canvasTop - 500 <= $(window).scrollTop() + $(window).height() and canvasBottom + 500 >= $(window).scrollTop()
        pagesToRender.push page
      else
        # TODO: Only if page is not having a user selection (multipage selection in progress)
        pagesToRemove.push page

    console.log "In @Highlighter.checkRender: call page.render (fills text-layer) for pages "
    console.log pagesToRender
    page.render() for page in pagesToRender
    console.log "In @Highlighter.checkRender: call page.remove for pages "
    console.log pagesToRemove
    page.remove() for page in pagesToRemove

    return # Make sure CoffeeScript does not return anything

  destroy: =>
    $(window).off '.highlighter'

    # We stop handles here and not just leave it to Deps.autorun to do it to cleanup in the right order
    @_highlightsHandle?.stop()
    @_highlightsHandle = null
    @_highlightLocationHandle?.stop()
    @_highlightLocationHandle = null

    page.destroy() for page in @_pages
    @_pages = []
    @_numPages = null # To disable any asynchronous _checkHighlighting
    #@_annotator.destroy() if @_annotator
    #@_annotator = null # To release any cyclic memory
    @_$displayWrapper = null # To release any cyclic memory

  extractText: (pageNumber) =>
    console.log "In @Highlighter.extractText: extracted text for page " + pageNumber + " is "
    console.log @_pages[pageNumber - 1]

    @_pages[pageNumber - 1].extractText()

  getNumPages: =>
    @_numPages

  getTextLayer: (pageNumber) =>
    @_pages[pageNumber - 1].$displayPage.find('.text-layer').get(0)

  hasTextContent: (pageNumber) =>
    @_pages[pageNumber - 1]?.hasTextContent()

  imageLayer: (pageNumber) =>
    @_pages[pageNumber - 1].imageLayer()

  isPageRendered: (pageNumber) =>
    @_pages[pageNumber - 1]?.isRendered()

  pageRendered: (page) =>
    # We update the mapper for new page
    @_annotator?.domMapper?.pageRendered page.pageNumber

  pageRemoved: (page) =>
    # We update the mapper for removed page
    @_annotator?.domMapper?.pageRemoved page.pageNumber

  setNumPages: (@_numPages) =>

  setPage: (viewport, pdfPage) =>
    # Initialize the page
    @_pages[pdfPage.pageNumber - 1] = new Page @, viewport, pdfPage
    console.log "In @Highlighter.setPage: @_pages[pdfPage.pageNumber - 1] is "
    console.log @_pages[pdfPage.pageNumber - 1]

  setTextContent: (pageNumber, textContent) =>
    @_pages[pageNumber - 1].textContent = textContent

    @_pages[pageNumber - 1]._generateTextSegments()
    #console.log @_pages[pageNumber - 1]

    #@_checkHighlighting()

  textLayer: (pageNumber) =>
    @_pages[pageNumber - 1].textLayer()

  _checkHighlighting: =>
    return unless @_pages.length is @_numPages

    return unless _.every @_pages, (page) -> page.hasTextContent()

    @_annotator._scan()

    @_highlightsHandle = Highlight.documents.find(
      'publication._id': Session.get 'currentPublicationId'
    ).observeChanges
      added: (id, fields) =>
        @highlightAdded id, fields
      changed: (id, fields) =>
        @highlightChanged id, fields
      removed: (id) =>
        @highlightRemoved id

    @_highlightLocationHandle = Deps.autorun =>
      @_annotator._selectHighlight Session.get 'currentHighlightId'
