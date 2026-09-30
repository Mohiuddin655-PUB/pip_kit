import AVFoundation
import AVKit
import Accelerate
import Flutter
import UIKit

/// iOS Picture in Picture.
///
/// AVKit only grants a floating window to a video layer, so there are exactly
/// two ways content gets into one:
///
/// * `video` — an `AVPlayerLayer` that is already on screen (for example
///   `video_player` in platform-view mode) is handed to the system as is.
/// * `widget` — Flutter captures a widget and sends it here frame by frame;
///   the frames are enqueued on an `AVSampleBufferDisplayLayer`, which the
///   system accepts as a video source.
///
/// In both cases the controller is built while the app is in the foreground and
/// kept, because that is the only time automatic entry can be armed.
public class PipKitPlugin: NSObject, FlutterPlugin, AVPictureInPictureControllerDelegate,
  AVPictureInPictureSampleBufferPlaybackDelegate
{
  private let channel: FlutterMethodChannel

  private var controller: AVPictureInPictureController?
  private var statusObservation: NSKeyValueObservation?
  private var autoEnter = false
  private var isOpen = false

  /// The player layer the controller was built for, in `video` mode.
  private weak var playerLayer: AVPlayerLayer?

  /// The view whose layer receives captured frames, in `widget` mode.
  private var frameView: PipKitFrameView?
  private var frameSize = CGSize(width: 9, height: 16)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pip_kit", binaryMessenger: registrar.messenger())
    let instance = PipKitPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "isSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "configure":
      result(configure(arguments))
    case "enter":
      enter(result)
    case "exit":
      result(exit())
    case "release":
      release()
      result(true)
    case "pushFrame":
      pushFrame(arguments)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Configure

  private func configure(_ arguments: [String: Any]) -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return false }
    autoEnter = arguments["autoEnter"] as? Bool ?? false
    let width = arguments["aspectRatioWidth"] as? Int ?? 9
    let height = arguments["aspectRatioHeight"] as? Int ?? 16
    frameSize = CGSize(width: max(width, 1), height: max(height, 1))

    // No window is granted to an app whose audio session is inactive, even for
    // silent content.
    activateAudioSession()

    let mode = arguments["mode"] as? String ?? "widget"
    let ready = mode == "video" ? prepareVideo() : prepareFrames()
    applyAutoEnter()
    return ready
  }

  private func activateAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      if session.category != .playback {
        try session.setCategory(.playback, mode: .moviePlayback)
      }
      try session.setActive(true)
    } catch {
      NSLog("pip_kit: could not activate the audio session: \(error)")
    }
  }

  private func applyAutoEnter() {
    controller?.canStartPictureInPictureAutomaticallyFromInline = autoEnter
  }

  private func adopt(_ newController: AVPictureInPictureController?) {
    statusObservation?.invalidate()
    controller = newController
    newController?.delegate = self
    statusObservation = newController?.observe(\.isPictureInPictureActive, options: [.new]) {
      [weak self] _, change in
      guard let self, let active = change.newValue else { return }
      self.report(active)
    }
  }

  private func report(_ open: Bool) {
    guard open != isOpen else { return }
    isOpen = open
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("onStatus", arguments: open)
    }
  }

  // MARK: - Video mode

  private func prepareVideo() -> Bool {
    removeFrameView()
    guard let layer = findPlayerLayer() else {
      NSLog("pip_kit: no AVPlayerLayer on screen; mount a platform-view player first")
      return false
    }
    // Keep the controller while it still belongs to the layer on screen.
    if controller != nil, playerLayer === layer { return true }
    playerLayer = layer
    adopt(AVPictureInPictureController(playerLayer: layer))
    return controller != nil
  }

  private func findPlayerLayer() -> AVPlayerLayer? {
    guard let root = keyWindow()?.rootViewController?.view else { return nil }
    return findPlayerLayer(in: root)
  }

  private func findPlayerLayer(in view: UIView) -> AVPlayerLayer? {
    if let layer = view.layer as? AVPlayerLayer, layer.player != nil { return layer }
    for sublayer in view.layer.sublayers ?? [] {
      if let layer = sublayer as? AVPlayerLayer, layer.player != nil { return layer }
    }
    for subview in view.subviews {
      if let layer = findPlayerLayer(in: subview) { return layer }
    }
    return nil
  }

  private func keyWindow() -> UIWindow? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first(where: { $0.isKeyWindow }) ?? windows.first
  }

  // MARK: - Widget mode

  private func prepareFrames() -> Bool {
    playerLayer = nil
    guard let root = keyWindow()?.rootViewController?.view else { return false }

    if frameView == nil {
      // The source layer has to be in the view hierarchy for the system to
      // accept it. It sits behind the Flutter view, which covers it.
      let view = PipKitFrameView(frame: CGRect(origin: .zero, size: CGSize(width: 90, height: 160)))
      view.isUserInteractionEnabled = false
      view.displayLayer.videoGravity = .resizeAspect
      root.insertSubview(view, at: 0)
      frameView = view

      let source = AVPictureInPictureController.ContentSource(
        sampleBufferDisplayLayer: view.displayLayer,
        playbackDelegate: self
      )
      adopt(AVPictureInPictureController(contentSource: source))
    }
    let scale = 160 / max(frameSize.height, 1)
    frameView?.frame = CGRect(
      x: 0, y: 0, width: frameSize.width * scale, height: frameSize.height * scale)
    return controller != nil
  }

  private func removeFrameView() {
    guard frameView != nil else { return }
    frameView?.removeFromSuperview()
    frameView = nil
    adopt(nil)
  }

  private func pushFrame(_ arguments: [String: Any]) {
    guard let view = frameView,
      let data = (arguments["bytes"] as? FlutterStandardTypedData)?.data,
      let width = arguments["width"] as? Int,
      let height = arguments["height"] as? Int,
      width > 0, height > 0, data.count >= width * height * 4,
      let sample = makeSampleBuffer(rgba: data, width: width, height: height)
    else { return }

    let layer = view.displayLayer
    if layer.status == .failed { layer.flush() }
    layer.enqueue(sample)
  }

  /// Wraps one RGBA frame in a sample buffer the display layer will show as
  /// soon as it arrives.
  private func makeSampleBuffer(rgba: Data, width: Int, height: Int) -> CMSampleBuffer? {
    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      kCVPixelBufferCGImageCompatibilityKey: true,
    ]
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      attributes as CFDictionary, &pixelBuffer)
    guard let buffer = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let destination = CVPixelBufferGetBaseAddress(buffer) else { return nil }

    // Flutter hands over RGBA; the pixel buffer is BGRA.
    rgba.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
      var sourceBuffer = vImage_Buffer(
        data: UnsafeMutableRawPointer(mutating: source.baseAddress),
        height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: width * 4)
      var destinationBuffer = vImage_Buffer(
        data: destination,
        height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: CVPixelBufferGetBytesPerRow(buffer))
      let bgraFromRgba: [UInt8] = [2, 1, 0, 3]
      vImagePermuteChannels_ARGB8888(
        &sourceBuffer, &destinationBuffer, bgraFromRgba, vImage_Flags(kvImageNoFlags))
    }

    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
    guard let formatDescription = format else { return nil }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: buffer,
      formatDescription: formatDescription, sampleTiming: &timing, sampleBufferOut: &sample)

    if let sample,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)
    {
      let first = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        first,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    return sample
  }

  // MARK: - Enter / exit

  private func enter(_ result: @escaping FlutterResult) {
    guard let controller else {
      result(false)
      return
    }
    if controller.isPictureInPictureActive {
      result(true)
      return
    }
    // The system refuses a window for a player that is not playing.
    if let player = playerLayer?.player, player.timeControlStatus != .playing {
      player.play()
    }
    DispatchQueue.main.async { [weak self] in
      controller.startPictureInPicture()
      // AVKit reports the outcome through its delegate a moment later.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        result(self?.controller?.isPictureInPictureActive ?? false)
      }
    }
  }

  private func exit() -> Bool {
    guard let controller, controller.isPictureInPictureActive else { return false }
    controller.stopPictureInPicture()
    return true
  }

  private func release() {
    autoEnter = false
    if controller?.isPictureInPictureActive == true {
      controller?.stopPictureInPicture()
    }
    removeFrameView()
    adopt(nil)
    playerLayer = nil
  }

  // MARK: - AVPictureInPictureControllerDelegate

  public func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    report(true)
  }

  public func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    report(false)
    // The controller is kept: releasing it here would stop automatic entry
    // from working a second time.
    applyAutoEnter()
  }

  public func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    NSLog("pip_kit: failed to start Picture in Picture: \(error)")
  }

  public func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    // The app was never dismissed, so there is nothing to rebuild.
    completionHandler(true)
  }

  // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

  public func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool
  ) {
    // The window's own play/pause button. There is nothing to pause natively —
    // the frames come from Flutter — so the tap is passed up as an action.
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("onAction", arguments: playing ? "ios.play" : "ios.pause")
    }
  }

  public func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    // An unbounded range marks the content as live, which hides the scrubber.
    CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  public func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    false
  }

  public func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  public func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }

  deinit {
    statusObservation?.invalidate()
  }
}

/// A view backed by the layer that captured frames are enqueued on.
final class PipKitFrameView: UIView {
  override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

  var displayLayer: AVSampleBufferDisplayLayer {
    // Guaranteed by `layerClass`.
    layer as! AVSampleBufferDisplayLayer
  }
}
