MAX_TEXT_LAYER_SEGMENTS_TO_RENDER = 100000

class @Page
  constructor: (@highlighter, @viewport, @pdfPage) ->
    @pageNumber = @pdfPage.pageNumber

    @textContent = null
    @textSegments = []
    @imageSegments = []
    @textSegmentsDone = false
    @imageLayerDone = null
    @highlightsEnabled = false
    @rendering = false

    @_extractedText = null

    @$displayPage = $("#display-page-#{ @pageNumber }", @highlighter._$displayWrapper)

    console.log "In @Page.constructor: the new page instance for page " + @pdfPage.pageNumber + " is "
    console.log @

  extractText: =>
    return @_extractedText unless @_extractedText is null

    @_extractedText = Utils.pdfExtractText @textContent    

  hasTextContent: =>
    @textContent isnt null

  imageLayer: =>
    console.log "In @Page.imageLayer: Entering @Page.imageLayer for page " + @pageNumber

    beginLayout: =>
      console.log "In @Page.imageLayer: Begin Image Layer for page " + @pageNumber
      @imageLayerDone = false

    endLayout: =>
      console.log "In @Page.imageLayer: End Image Layer for page " + @pageNumber
      @imageLayerDone = true

      console.log "In @Page.imageLayer: about to @_enableHighlights() for page " + @pageNumber
      @_enableHighlights()

    appendImage: (geom) =>
      console.log "In @Page.imageLayer: Start appendImage for page " + @pageNumber
      @imageSegments.push Utils.pdfImageSegment geom

  isRendered: =>
    return false unless @highlightsEnabled

    return false if @rendering

    not @$displayPage.find('.text-layer-dummy').is(':visible')

  padTextSegments: (event) =>
    position = @_eventToPosition event

    # First check if we are directly above a text segment. We could combine this
    # with _findLastLeftUpTextSegment below, but we also want to handle the case
    # when we are directly above an unselectable segment.
    segmentIndex = @_overTextSegment position

    if segmentIndex isnt -1
      @_padTextSegment position, segmentIndex
      return

    # Find latest text layer segment in text flow on the page before the given position
    segmentIndex = @_findLastLeftUpTextSegment position

    # segmentIndex might be -1, but @_distanceY returns
    # infinity in this case, so things work out
    if @_distanceY(position, @textSegments[segmentIndex]?.boundingBox) is 0
      # A clear case, we are directly over a segment y-wise. This means that
      # segment is to the left of mouse position (because we searched for
      # all segments to the left and up of the position and we already checked
      # if we are directly over a segment). This is the segment we want to pad.
      @_padTextSegment position, segmentIndex
      return

    # So we are close to the segment we want to pad, but we might currently have
    # a segment which is in the middle of the text line above our position, so we
    # search for the last text segment in that line, before it goes to the next
    # (our, where our position is) line.
    # On the other hand, segmentIndex might be -1 because we are on the left border
    # of the page and there are no text segments to the left and up. So we as well
    # do a search from the beginning of the page to the last text segment on the
    # text line just above our position.
    # We keep track of the number of skipped unselectable segments to not increase
    # segmentIndex until we get to a selectable segment again (if we do at all).
    skippedUnselectable = 0
    while @textSegments[segmentIndex + skippedUnselectable + 1]
      segment = @textSegments[segmentIndex + skippedUnselectable + 1]
      if segment.unselectable
        skippedUnselectable++
      else
        segmentIndex += skippedUnselectable
        skippedUnselectable = 0
        if segment.boundingBox.top + segment.boundingBox.height > position.top
          break
        else
          segmentIndex++

    # segmentIndex can still be -1 if there are no text segments before
    # the mouse position, so let's simply find closest segment and pad that.
    # Not necessary for Chrome. There you can start selecting without being
    # over any text segment and it will correctly start when you move over
    # one. But in Firefox you have to start selecting over a text segment
    # (or padded text segment) to work correctly later on.
    segmentIndex = @_findClosestTextSegment position if segmentIndex is -1

    # segmentIndex can still be -1 if there are no text segments on
    # the page at all, then we do not have aynthing to do
    @_padTextSegment position, segmentIndex if segmentIndex isnt -1

    return # Make sure CoffeeScript does not return anything

  remove: =>
    assert not @rendering

    $textLayerDummy = @$displayPage.find('.text-layer-dummy')

    return if $textLayerDummy.is(':visible')

    @$displayPage.off 'mousemove.highlighter'

    @$displayPage.find('.text-layer').empty()

    for segment in @textSegments
      segment.$domElement = null

    $textLayerDummy.show()

    @highlighter.pageRemoved @

  render: =>
    console.log "In @Page.render: started function call for page " + @pageNumber
    assert @highlightsEnabled

    $textLayerDummy = @$displayPage.find('.text-layer-dummy')
    console.log "In @Page.render: $textLayerDummy for page " + @pageNumber + " is "
    console.log $textLayerDummy

    return unless $textLayerDummy.is(':visible')
    console.log "In @Page.render: $textLayerDummy for page " + @pageNumber + " is :visible"

    return if @rendering
    console.log "In @Page.render: set @rendering for page " + @pageNumber + " to true"
    @rendering = true

    $textLayerDummy.hide()
    console.log "In @Page.render: hide $textLayerDummy for page " + @pageNumber


    divs = for segment, index in @textSegments
      segment.$domElement = $('<div/>').addClass('text-layer-segment').css(segment.style).text(segment.text).data
        pageNumber: @pageNumber
        index: index
    console.log "In @Page.render: segments div for page " + @pageNumber + " is "
    #console.log divs


    # There is no use rendering so many divs to make browser useless
    # TODO: Report this to the server? Or should we simply discover such PDFs already on the server when processing them?
    console.log "In @Page.render: $displayPage before appending segments is for page " + @pageNumber + " is"
    console.log @$displayPage
    @$displayPage.find('.text-layer').append divs if divs.length <= MAX_TEXT_LAYER_SEGMENTS_TO_RENDER
    console.log "In @Page.render: $displayPage after appending segments is for page " + @pageNumber + " is"
    console.log @$displayPage

    # for marking text by mouse
    @$displayPage.on 'mousemove.highlighter', console.log "Mouse clicked and moving"
    @$displayPage.on 'mousemove.highlighter', @padTextSegments

    console.log "In @Page.render: setting page.rendering to false for page " + @pageNumber
    @rendering = false

    console.log "In @Page.render: calling @highlighter.pageRendered for page " + @pageNumber
    @highlighter.pageRendered @

  _cleanTextSegments: =>
    # We traverse from the end and search for segments which should be before the first segment
    # and mark them unselectable. The rationale is that those segments which are spatially positioned
    # before the first segment, but are out-of-order in the array are watermarks or headers and other
    # elements not connected with the content, but they interfere with highlighting. It seems they are
    # simply appended at the end so we search them only near the end. We still allow unselectable
    # segments to be selected in the browser if user is directly over it.
    # See https://github.com/peerlibrary/peerlibrary/issues/387

    # Few segments can be correctly ordered among those at the end. For example, page numbers.
    threshold = 5 # segments, currently chosen completely arbitrary (just that it is larger than 1)
    for segment in @textSegments by -1
      if segment.boundingBox.left >= @textSegments[0].boundingBox.left and segment.boundingBox.top >= @textSegments[0].boundingBox.top
        threshold--
        break if threshold is 0
        continue
      segment.unselectable = true

  _distanceX: (position, area) =>
    return Number.POSITIVE_INFINITY unless area

    distanceXLeft = Math.abs(position.left - area.left)
    distanceXRight = Math.abs(position.left - (area.left + area.width))

    if position.left > area.left and position.left < area.left + area.width
      distanceX = 0
    else
      distanceX = Math.min(distanceXLeft, distanceXRight)

    distanceX

  _distanceY: (position, area) =>
    return Number.POSITIVE_INFINITY unless area

    distanceYTop = Math.abs(position.top - area.top)
    distanceYBottom = Math.abs(position.top - (area.top + area.height))

    if position.top > area.top and position.top < area.top + area.height
      distanceY = 0
    else
      distanceY = Math.min(distanceYTop, distanceYBottom)

    distanceY

  _distance: (position, area) =>
    return Number.POSITIVE_INFINITY unless area

    distanceX = @_distanceX position, area
    distanceY = @_distanceY position, area

    Math.sqrt(distanceX * distanceX + distanceY * distanceY)

  _enableHighlights: =>
    console.log "In @Page._enableHighlights: Enable Highlights for page " + @pageNumber
    console.log "In @Page._enableHighlights: Text segment for page " + @pageNumber + " are done: " + @textSegmentsDone
    console.log "In @Page._enableHighlights: Image layer for page " + @pageNumber + " is done: " + @imageLayerDone
    return unless @textSegmentsDone and @imageLayerDone

    # Highlights already enabled for this page
    return if @highlightsEnabled
    @highlightsEnabled = true
    console.log "In @Page._enableHighlights for page " + @pageNumber + ": " + @highlightsEnabled

    # For debugging
    #@_showSegments()
    #@_showTextSegments()

  _eventToPosition: (event) =>
    $canvas = @$displayPage.find('canvas')

    offset = $canvas.offset()

    left: event.pageX - offset.left
    top: event.pageY - offset.top

  # Finds a text layer segment which is it to the left and up of the given position
  # and has highest index. Highest index means it is latest in the text flow of the
  # page. So we are searching for for latest text layer segment in text flow on the
  # page before the given position. Left and up is what is intuitively right for
  # text which flows left to right, top to bottom.
  _findLastLeftUpTextSegment: (position) =>
    segmentIndex = -1
    for segment, index in @textSegments when not segment.unselectable
      # We allow few additional pixels so that position can be slightly to the left
      # of the text segment. This helps when user is with mouse between two columns
      # of text. With this the text segment to the right (in the right column) is
      # still selected when mouse is a bit to the left of the right column. Otherwise
      # selection would immediately jump the the left column. Good text editors put
      # this location when selection switches from right column to left column to the
      # middle between columns, but we do not really have information about the columns
      # so we at least make it a bit easier to the user. The only issue would be if
      # columns would be so close that those additional pixels would move into the left
      # column. This is unlikely if we keep the number small.
      segmentIndex = index if segment.boundingBox.left <= position.left + 10 * @viewport.scale and segment.boundingBox.top <= position.top and index > segmentIndex

    segmentIndex

  # Simple search for closest text layer segment by euclidean distance
  _findClosestTextSegment: (position) =>
    closestSegmentIndex = -1
    closestDistance = Number.POSITIVE_INFINITY

    for segment, index in @textSegments when not segment.unselectable
      distance = @_distance position, segment.boundingBox
      if distance < closestDistance
        closestSegmentIndex = index
        closestDistance = distance

    closestSegmentIndex

  _generateTextSegments: =>
    for geom in @textContent.items

      # We transform text segments into a more readable object
      segment = Utils.pdfTextSegment @viewport, geom, @textContent.styles

      continue if segment.isWhitespace or not segment.hasArea

      # We push the text segments into our @_pages.textSegments Array
      @textSegments.push segment

    @_cleanTextSegments()

    @textSegmentsDone = true

  _overTextSegment: (position) =>
    segmentIndex = -1
    # We still want to allow unselectable segments to be selected in the
    # browser if user is directly over it, so we go over all segments here.
    for segment, index in @textSegments
      if @_distanceX(position, segment.boundingBox) + @_distanceY(position, segment.boundingBox) is 0
        segmentIndex = index
        break

    segmentIndex

  # Pads a text layer segment (identified by index) so that its padding comes
  # under the position of the mouse. This makes text selection in browsers
  # behave like mouse is still over the text layer segment DOM element, even
  # when mouse is moved from it, for example, when dragging selection over empty
  # space in pages where there are no text layer segments.
  _padTextSegment: (position, index) =>
    segment = @textSegments[index]
    distance = @_distance position, segment.boundingBox
    $dom = segment.$domElement

    # Text layer segments can be rotated and scaled along x-axis
    angle = segment.angle
    scaleX = segment.scaleX

    # Padding is scaled later on, so we apply scaling inversely here so that it is
    # exact after scaling later on. Without that when scaling is < 1, when user moves
    # far away from the text segment, padding falls behind and does not reach mouse
    # position anymore.
    # Additionally, we add few pixels so that user can move mouse fast and still stay in.
    padding = distance / scaleX + 20 * @viewport.scale

    # Padding (and text) rotation transformation is done through CSS and
    # we have to match it for margin, so we compute here margin under rotation.
    # 2D vector rotation: http://www.siggraph.org/education/materials/HyperGraph/modeling/mod_tran/2drota.htm
    # x' = x cos(f) - y sin(f), y' = x sin(f) + y cos(f)
    # Additionally, we use CSS scaling transformation along x-axis on padding
    # (and text), so we have to scale margin as well.
    left = padding * (scaleX * Math.cos(angle) - Math.sin(angle))
    top = padding * (scaleX * Math.sin(angle) + Math.cos(angle))

    @$displayPage.find('.text-layer-segment').css
      padding: 0
      margin: 0

    # Optimization if position is to the right and down of the segment. We do this
    # because modifying both margin and padding slightly jitters text segment around
    # because of rounding to pixel coordinates (text is scaled and rotated so margin
    # and padding values do not fall nicely onto pixel coordinates).
    if segment.boundingBox.left <= position.left and segment.boundingBox.top <= position.top
      $dom.css
        paddingRight: padding
        paddingBottom: padding
      return

    # Otherwise we apply padding all around the text segment DOM element and do not
    # really care where the mouse position is, we have to change both margin and
    # padding anyway.
    # We counteract text content position change introduced by padding by setting
    # negative margin. With this, text content stays in place, but DOM element gets a
    # necessary padding.
    $dom.css
      marginLeft: -left
      marginTop: -top
      padding: padding
