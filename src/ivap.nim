import std/[os, parseopt, sets, options, asyncfutures, sequtils, sugar, tables]
import fusion/matching

import owlkettle
import owlkettle/[playground, adw]

type GridViewModel = object
  pixbufCache: Table[string, Pixbuf]
  paths: seq[string]

proc init(T: type GridViewModel, paths: seq[string], pixbufCache: Table[string, Pixbuf]): T =
  echo paths
  result = T(paths: paths, pixbufCache: pixbufCache)

viewable GridView:
  m: GridViewModel

method view(self: GridViewModel): Widget =
  result = gui:
    Grid(spacing=4, margin=4):
      for image in self.paths:
        Label(text="image")

type ImageViewModel = object
  pixbufCache: Table[string, Pixbuf]
  path: string
  loading: bool

proc init(T: type ImageViewModel, path: string, pixbufCache: Table[string, Pixbuf]): T =
  result = T(path: path, pixbufCache: pixbufCache)

viewable ImageView:
  m: ImageViewModel

method view(self: ImageViewState): Widget =
  if not self.m.pixbufCache.hasKey(self.m.path) and not self.m.loading:
    let future = self.m.path.loadPixbufAsync()
    proc callback(buf: Future[Pixbuf]) =
      self.m.loading = false
      self.m.pixbufCache[self.m.path] = buf.read()
      discard self.redraw()
    future.addCallback(callback)
    self.m.loading = true

  let pixbuf = 
    if self.m.pixbufCache.hasKey(self.m.path):
      self.m.pixbufCache[self.m.path]
    else:
      nil

  result = gui:
    CenterBox:
      if pixbuf.isNil or self.m.loading:
        Label(text = "Loading...")
      else:
        Picture:
          pixbuf = pixbuf
          contentFit = ContentScaleDown

type
  AppImageView = enum
    single
    grid

  AppModel = ref object
    pixbufCache: Table[string, Pixbuf]
    view = single
    paths: seq[string]
    activePath: int
    selecting: bool

proc activeImagePath(self: AppModel): string =
  result = ""
  if self.activePath >= 0 and self.activePath < self.paths.len():
    return self.paths[self.activePath]

proc nextImage(self: AppModel) =
  if self.activePath < self.paths.len() - 1:
    inc self.activePath
  else:
    self.activePath = 0

proc prevImage(self: AppModel) =
  if self.activePath > 0:
    dec self.activePath
  else:
    self.activePath = self.paths.len() - 1

viewable App:
  m: AppModel

method view(app: AppState): Widget =
  result = gui:
    Window:
      title = "ivap"
      defaultSize = (1280, 720)
      Box(orient = OrientY, margin = 0, spacing=4):
        Box(orient = OrientX, margin = 4):
          if app.m.view == single:
            Label(text=app.m.activeImagePath()) {.expand: false, hAlign: AlignCenter.}

          Box(orient=OrientX, spacing=4) {.expand: true, vAlign: AlignStart, hAlign: AlignEnd.}:
            if app.m.selecting:
              Button(text="Select"):
                proc clicked() =
                  stdout.write(app.m.activeImagePath())
                  app.closeWindow()

            Button(text="Grid"):
              proc clicked() =
                if app.m.view == single:
                  app.m.view = grid
                else:
                  app.m.view = single
                discard app.redraw()

        Box(orient=OrientX) {.hAlign: AlignCenter, expand: true.}:
          let path = app.m.paths[app.m.activePath]
          Overlay {.expand: true.}:
            Box(orient=OrientX) {.addOverlay, vAlign: AlignCenter.}:
              if app.m.view == single:
                Box(orient=OrientX) {.hAlign: AlignStart.}:
                  Button(text="<") {.expand: false.}:
                    style=[ButtonCircular]
                    proc clicked() =
                      app.m.prevImage()
                Box(orient=OrientX) {.hAlign: AlignEnd.}:
                  Button(text=">") {.expand: false.}:
                    style=[ButtonCircular]
                    proc clicked() =
                      app.m.nextImage()
            CenterBox:
              if app.m.view == single:
                ImageView(m = ImageViewModel.init(path, app.m.pixbufCache))
              else:
                GridView(m = GridViewModel.init(app.m.paths, app.m.pixbufCache))

const ImageExtensions = [ "png", "jpg", "jpeg" ].toHashSet()

proc toImagePaths(paths: seq[string]): seq[string] =
  ## Take a list of paths including directories
  ## and find all of the paths to images
  result = @[]
  for path in paths:
    if path.dirExists() and not path.fileExists():
      for (kind, subPath) in walkDir(path):
        if kind != pcFile:
          continue
        let (_, _, ext) = subPath.splitFile()
        if ext[1 ..< ext.len] notin ImageExtensions:
          continue
        result.add(subPath)
    if path.fileExists():
      let (_, _, ext) = path.splitFile()
      if ext[1 ..< ext.len] notin ImageExtensions:
        continue
      result.add(path)

proc start() =
  var paths: seq[string] = @[]

  var selecting = false

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      if p.key == "selecting" or p.key == "s":
        selecting = true
    of cmdArgument:
      paths.add(p.key)

  let imagePaths = paths.toImagePaths()

  adw.brew(gui(App(
    m = AppModel(
      pixbufCache: initTable[string, Pixbuf](),
      paths: imagePaths,
      activePath: 0,
      selecting: selecting))))

when isMainModule:
  start()
