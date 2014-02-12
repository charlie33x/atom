{remove, last} = require 'underscore-plus'
{Model} = require 'theorist'
Q = require 'q'
Serializable = require 'serializable'
Delegator = require 'delegato'
PaneContainer = require './pane-container'
Pane = require './pane'

# Public: Represents the view state of the entire window, including the panes at
# the center and panels around the periphery.
#
# An instance of this class is always available as the `atom.workspace` global.
module.exports =
class Workspace extends Model
  atom.deserializers.add(this)
  Serializable.includeInto(this)

  @delegatesProperty 'activePane', 'activePaneItem', toProperty: 'paneContainer'
  @delegatesMethod 'getPanes', 'saveAll', 'activateNextPane', 'activatePreviousPane',
    toProperty: 'paneContainer'

  @properties
    paneContainer: -> new PaneContainer
    fullScreen: false
    destroyedItemUris: -> []

  constructor: ->
    super
    @subscribe @paneContainer, 'item-destroyed', @onPaneItemDestroyed
    atom.project.registerOpener (filePath) =>
      switch filePath
        when 'atom://.atom/stylesheet'
          @open(atom.themes.getUserStylesheetPath())
        when 'atom://.atom/keymap'
          @open(atom.keymap.getUserKeymapPath())
        when 'atom://.atom/config'
          @open(atom.config.getUserConfigPath())
        when 'atom://.atom/init-script'
          @open(atom.getUserInitScriptPath())

  # Called by the Serializable mixin during deserialization
  deserializeParams: (params) ->
    params.paneContainer = PaneContainer.deserialize(params.paneContainer)
    params

  # Called by the Serializable mixin during serialization.
  serializeParams: ->
    paneContainer: @paneContainer.serialize()
    fullScreen: atom.isFullScreen()

  # Public: Asynchronously opens a given a filepath in Atom.
  #
  # filePath - A {String} file path.
  # options  - An options {Object} (default: {}).
  #   :initialLine - A {Number} indicating which line number to open to.
  #   :split - A {String} ('left' or 'right') that opens the filePath in a new
  #            pane or an existing one if it exists.
  #   :changeFocus - A {Boolean} that allows the filePath to be opened without
  #                  changing focus.
  #   :searchAllPanes - A {Boolean} that will open existing editors from any pane
  #                     if the filePath is already open (default: false)
  #
  # Returns a promise that resolves to the {Editor} for the file URI.
  open: (filePath, options={}) ->
    changeFocus = options.changeFocus ? true
    filePath = atom.project.resolve(filePath)
    initialLine = options.initialLine
    searchAllPanes = options.searchAllPanes
    split = options.split
    uri = atom.project.relativize(filePath)

    pane = switch split
      when 'left'
        @activePane.findLeftmostSibling()
      when 'right'
        @activePane.findOrCreateRightmostSibling()
      else
        if searchAllPanes
          @paneContainer.paneForUri(uri) ? @activePane
        else
          @activePane

    Q(pane.itemForUri(uri) ? atom.project.open(filePath, options))
      .then (editor) =>
        if not pane
          pane = new Pane(items: [editor])
          @paneContainer.root = pane

        @itemOpened(editor)
        pane.activateItem(editor)
        pane.activate() if changeFocus
        @emit "uri-opened"
        editor
      .catch (error) ->
        console.error(error.stack ? error)

  # Only used in specs
  openSync: (uri, options={}) ->
    {initialLine} = options
    # TODO: Remove deprecated changeFocus option
    activatePane = options.activatePane ? options.changeFocus ? true
    uri = atom.project.relativize(uri)

    if uri?
      editor = @activePane.itemForUri(uri) ? atom.project.openSync(uri, {initialLine})
    else
      editor = atom.project.openSync()

    @activePane.activateItem(editor)
    @itemOpened(editor)
    @activePane.activate() if activatePane
    editor

  # Public: Reopens the last-closed item uri if it hasn't already been reopened.
  reopenItemSync: ->
    if uri = @destroyedItemUris.pop()
      @openSync(uri)

  # Public: save the active item.
  saveActivePaneItem: ->
    @activePane?.saveActiveItem()

  # Public: save the active item as.
  saveActivePaneItemAs: ->
    @activePane?.saveActiveItemAs()

  # Public: destroy/close the active item.
  destroyActivePaneItem: ->
    @activePane?.destroyActiveItem()

  # Public: destroy/close the active pane.
  destroyActivePane: ->
    @activePane?.destroy()

  # Public: Returns an {Editor} if the active pane item is an {Editor},
  # or null otherwise.
  getActiveEditor: ->
    @activePane?.getActiveEditor()

  increaseFontSize: ->
    atom.config.set("editor.fontSize", atom.config.get("editor.fontSize") + 1)

  decreaseFontSize: ->
    fontSize = atom.config.get("editor.fontSize")
    atom.config.set("editor.fontSize", fontSize - 1) if fontSize > 1

  resetFontSize: ->
    atom.config.restoreDefault("editor.fontSize")

  # Removes the item's uri from the list of potential items to reopen.
  itemOpened: (item) ->
    if uri = item.getUri?()
      remove(@destroyedItemUris, uri)

  # Adds the destroyed item's uri to the list of items to reopen.
  onPaneItemDestroyed: (item) =>
    if uri = item.getUri?()
      @destroyedItemUris.push(uri)

  # Called by Model superclass when destroyed
  destroyed: ->
    @paneContainer.destroy()
