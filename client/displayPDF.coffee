Template.publication.rendered = ->
  $('.selection-layer').forwardMouseEvents()

  tpl = UI._templateInstance()
  pdfUrl = tpl.data.url
  #PDFUtils.showPDF(pdfUrl, document.getElementById('display-wrapper'))


Template.publicationDisplay.created = ->
  @_displayHandle = null
  @_displayWrapper = null


Template.publicationDisplay.rendered = ->
  # We want to rendered the publication only if display wrapper DOM element has changed,
  # so we store a random ID in the DOM element so that we can check if it is an old or
  # new DOM element. We ignore rendered callbacks which happen for example because
  # display wrapper's child templates were rendered (eg., when one hovers over a highlight).
  return if @_displayWrapper?[0]?._displayWrapperId and @_displayWrapper[0]._displayWrapperId is @find('.display-wrapper')?[0]._displayWrapperId
  @_displayWrapper = @find '.display-wrapper'
  @_displayWrapper?[0]?._displayWrapperId = Random.id()

  @_displayHandle?.stop()
  @_displayHandle = Deps.autorun =>
    url = UI._templateInstance().data.url

    return unless url

    PDFUtils.show url, $(@_displayWrapper)

Template.publicationDisplay.destroyed = ->
  @_displayHandle?.stop()
  @_displayHandle = null
  @_displayWrapper = null

makePercentage = (x) ->
  100 * Math.max(Math.min(x, 1), 0)

# We do not have to use display wrapper position in computing viewport
# positions because we are just interested in how much display wrapper
# moved and scrollTop changes in sync with display wrapper moving.
# When scrollTop is 100px, 100px less of display wrapper is visible.

viewportTopPercentage = ->
  makePercentage($(window).scrollTop() / $('.viewer .display-wrapper').outerHeight(true))

viewportBottomPercentage = ->
  availableHeight = $(window).height() - $('header .container').height()
  scrollBottom = $(window).scrollTop() + availableHeight
  makePercentage(scrollBottom / $('.viewer .display-wrapper').outerHeight(true))

debouncedSetCurrentViewport = _.throttle (viewport) ->
  currentViewport.set viewport
,
  500

setViewportPosition = ($viewport) ->
  top = viewportTopPercentage()
  bottom = viewportBottomPercentage()
  $viewport.css
    top: "#{ top }%"
    # We are using top & height instead of top & bottom because
    # jQuery UI dragging is modifying only top and even if we
    # dynamically update bottom in drag or scroll event handlers,
    # height of the viewport still jitters as user drags. But the
    # the downside is that user cannot scroll pass the end of the
    # publication with scroller as jQuery UI stops dragging when
    # end reaches the edge of the containment. If we use top &
    # height we are dynamically making viewport smaller so this
    # is possible.
    height: "#{ bottom - top }%"

  displayHeight = $('.viewer .display-wrapper').height()
  debouncedSetCurrentViewport
    top: top * displayHeight / 100
    bottom: bottom * displayHeight / 100

scrollToOffset = (offset) ->
  # We round ourselves to make sure we are rounding in the same way accross all browsers.
  # Otherwise there is a conflict between what scroll to and how is the viewport then
  # positioned in the scroll event handler and what is the position of the viewport as we
  # are dragging it. This makes movement of the viewport not smooth.
  $(window).scrollTop Math.round(offset * $('.viewer .display-wrapper').outerHeight(true))

Template.publicationScroller.created = ->
  $(window).on 'scroll.publicationScroller resize.publicationScroller', (event) =>
    return unless publicationDOMReady.get()

    # We do not call setViewportPosition when dragging from scroll event
    # handler but directly from drag event handler because otherwise there
    # are two competing event handlers working on viewport position.
    # An example of the issue is if you drag fast with mouse below the
    # browser window edge if there are compething event handlers viewport
    # gets stuck and does not necessary go to the end position.
    setViewportPosition $(@find '.viewport') unless draggingViewport

    return # Make sure CoffeeScript does not return anything

Template.publicationScroller.rendered = ->
  console.log "In Template.publicationScroller.rendered: entered function"
  Tracker.autorun ->
    # Dependency on publicationDOMReady value is registered because we
    # are using it in sections helper as well, which means that rendered will
    # be called multiple times as publicationDOMReady changes
    console.log "In Template.publicationScroller.rendered: publicationDOMReady is " + publicationDOMReady.get()
    return unless publicationDOMReady.get()

    $viewport = $(@find '.viewport')
    console.log $viewport

    draggingViewport = false
    console.log "In Template.publicationScroller.rendered: draggingViewPort is " + draggingViewport

    $viewport.draggable
      containment: 'parent'
      axis: 'y'

      start: (event, ui) ->
        draggingViewport = true
        return # Make sure CoffeeScript does not return anything

      drag: (event, ui) ->
        $target = $(event.target)

        # It seems it is better to use $target.offset().top than ui.offset.top
        # because it seems to better represent real state of the viewport
        # position. A test is if you move fast the viewport to the end it
        # moves the publication exactly to the end of the last page and
        # not a bit before.
        viewportOffset = $target.offset().top - $target.parent().offset().top
        scrollToOffset viewportOffset / $target.parent().height()

        # Sync the position, especially the height. It can happen that user starts
        # dragging when viewport is smaller at the end of the page, when it get over
        # the publication end, so we want to enlarge the viewport to normal size when
        # user drags it up.
        setViewportPosition $(event.target)

        return # Make sure CoffeeScript does not return anything

      stop: (event, ui) ->
        draggingViewport = false
        return # Make sure CoffeeScript does not return anything

    setViewportPosition $viewport
    console.log "In Template.publicationScroller.rendered: set viewport "

    if startViewerOnPage
      $scroller = $(@find '.scroller')
      $sections = $scroller.find('.section')

      # Scroll browser viewport to display the desired publication page
      viewportOffset = $sections.eq(startViewerOnPage - 1).offset().top - $scroller.offset().top
      padding = $sections.eq(0).offset().top - $scroller.offset().top
      scrollToOffset (viewportOffset - padding) / $scroller.height()

      # Sync the position of the scroller viewport
      setViewportPosition $viewport

      globals.startViewerOnPage = null

Template.publicationScroller.helpers
  sections: ->
    return [] unless publicationDOMReady.get()

    $displayWrapper = $('.viewer .display-wrapper')
    displayTop = $displayWrapper.outerOffset().top
    displayHeight = $displayWrapper.outerHeight(true)
    for section in $displayWrapper.children()
      $section = $(section)

      heightPercentage: 100 * $section.height() / displayHeight
      topPercentage: 100 * ($section.offset().top - displayTop) / displayHeight

Template.publicationScroller.destroyed = ->
  $(window).off '.publicationScroller'

Template.publicationScroller.events
  'click .scroller': (event, template) ->
    # We want to move only on clicks outside the viewport to prevent conflicts between dragging and clicking
    return if $(event.target).is('.viewport')

    $scroller = $(template.find '.scroller')
    clickOffset = event.pageY - $scroller.offset().top
    scrollToOffset (clickOffset - $(template.find '.viewport').height() / 2) / $scroller.height()

    return # Make sure CoffeeScript does not return anything
